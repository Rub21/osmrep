# frozen_string_literal: true

require "set"

module Osmrep
  module Dump
    # Writes the full dump of the gpx source from a pg_dump file, with no
    # database. The small tables go to SQLite, then gpx_tracks is read once
    # and each trace goes to a worker process when all its rows came. The
    # rows of a trace are usually together, so few traces are open at a time.
    # When the open traces take more than buffer_limit bytes, they go to a
    # file that is sorted and written at the end.
    class Runner
      TABLE = "gpx_tracks"
      EXT = ".bz2"
      SORT = ["sort", "-t", "\t", "-k1,1n", "-k2,2n", "-k3,3n"].freeze
      BUFFER_LIMIT = 1 << 30
      F_SETPIPE_SZ = 1031 # Linux fcntl command, not in Ruby's Fcntl module
      PIPE_SIZE = 1 << 20

      attr_reader :input, :jobs, :logger

      def initialize(input:, work_dir:, jobs: 4, buffer_limit: BUFFER_LIMIT,
                     content_visibilities: Sources::Gpx::ALLOWED_CONTENT_VISIBILITIES, logger: nil)
        @input = input.is_a?(Input) ? input : Input.new(input)
        @work_dir = work_dir
        @jobs = Integer(jobs)
        @buffer_limit = buffer_limit
        @content_visibilities = content_visibilities
        @logger = logger
        raise Error, "jobs must be at least 1" if @jobs < 1
      end

      # Returns the number of traces written, skipped (not served) and
      # scattered (written from the sorted file). The timestamp of the dump
      # is when pg_dump ran.
      def run(output, timestamp: input.created_at)
        raise Error, "the dump is bzip2, the output must end with .bz2" unless output.end_with?(EXT)

        FileUtils.mkdir_p(File.dirname(output))
        Dir.mktmpdir("osmrep-dump-", @work_dir) do |work|
          @work = work
          build_metadata
          row_counts = scan
          counts = { :traces => 0, :skipped => 0, :scattered => 0 }
          parts, columns = write_traces(row_counts, counts)
          parts << write_scattered(columns, counts) if counts[:scattered].positive?
          join(output, parts, timestamp)
          logger&.info("wrote #{counts[:traces]} traces to #{output}")
          counts
        end
      end

      # Opens a file for writing, one bzip2 stream.
      def self.compress_to(path)
        File.open(path, "wb") do |file|
          IO.popen(%w[bzip2 -c], "w", :out => file) { |stdin| yield widen(stdin) }
        end
        raise Error, "bzip2 failed" unless $?.success? # rubocop:disable Style/SpecialGlobalVars

        path
      end

      # Pipe buffer of 1 MB instead of the 64 KB default, so each process in
      # the chain pg_restore -> reader -> worker -> bzip2 can run ahead of
      # the next one instead of waiting for it. 1 MB is the Linux limit for
      # a normal user. Linux only; elsewhere the pipe keeps its default size.
      def self.widen(pipe)
        pipe.fcntl(F_SETPIPE_SZ, PIPE_SIZE)
        pipe
      rescue SystemCallError, NotImplementedError
        pipe
      end

      private

      def metadata_path
        File.join(@work, "metadata.sqlite")
      end

      def scattered_path
        File.join(@work, "scattered.txt")
      end

      def build_metadata
        logger&.info("reading gpx_files, gpx_file_tags and users from #{input.path}")
        store = Metadata.build(metadata_path, :users => input.rows("users"), :traces => input.rows("gpx_files"),
                                              :tags => input.rows("gpx_file_tags"), :content_visibilities => @content_visibilities)
        logger&.info("#{store.count} traces to write")
        store.close
      end

      def scan
        logger&.info("counting the rows of each trace in #{TABLE}")
        input.read(TABLE, :ids_only => true) do |io|
          CopyReader.skip_to(io, TABLE)
          Scan.counts(io).tap { io.each_line { nil } }
        end
      end

      # The main pass. Returns the parts written and the columns of the table.
      def write_traces(row_counts, counts)
        columns = nil
        workers = nil
        scattered = Set.new
        File.open(scattered_path, "w") do |scattered_file|
          input.read(TABLE) do |io|
            columns = CopyReader.skip_to(io, TABLE)
            workers = []
            jobs.times { |k| workers << WorkerProcess.new(k, @work, columns, metadata_path, workers) }
            logger&.info("writing the traces with #{jobs} workers")
            hand_out(io, workers, row_counts, scattered, scattered_file)
            io.each_line { nil }
          end
        end
        parts = workers.map { |w| w.finish(counts) }
        counts[:scattered] = scattered.size
        [parts, columns]
      end

      # Keeps the rows of each trace until all of them came, then gives the
      # trace to the next worker. When the open traces take too much memory,
      # they go to the scattered file, and the rest of their rows too.
      def hand_out(io, workers, row_counts, scattered, scattered_file)
        open = Hash.new { |h, k| h[k] = [] }
        bytes = 0
        turn = -1
        while (line = io.gets)
          break if line == CopyReader::TERMINATOR

          id = Integer(line[/\A\d+/])
          next scattered_file.write(line) if scattered.include?(id)

          rows = open[id] << line
          bytes += line.bytesize
          next if rows.size < row_counts[id] && bytes <= @buffer_limit

          bytes = if rows.size == row_counts[id]
                    send_trace(open.delete(id), workers[turn = (turn + 1) % jobs], bytes)
                  else
                    spill(open, scattered, scattered_file)
                  end
        end
        spill(open, scattered, scattered_file)
      end

      def send_trace(rows, worker, bytes)
        worker.write(rows.join)
        bytes - rows.sum(&:bytesize)
      end

      def spill(open, scattered, scattered_file)
        logger&.info("writing #{open.size} open traces to the scattered file") unless open.empty?
        open.each do |id, rows|
          scattered.add(id)
          scattered_file.write(rows.join)
        end
        open.clear
        0
      end

      def write_scattered(columns, counts)
        logger&.info("writing the #{counts[:scattered]} scattered traces")
        part = File.join(@work, "part-scattered#{EXT}")
        store = Metadata.open(metadata_path)
        IO.popen({ "LC_ALL" => "C" }, SORT + ["-T", @work, scattered_path], "r") do |sorted|
          self.class.compress_to(part) do |out|
            Worker.new(store, :columns => columns).run(sorted, out).each { |key, value| counts[key] += value }
          end
        end
        raise Error, "sort failed" unless $?.success? # rubocop:disable Style/SpecialGlobalVars

        store.close
        part
      end

      # header + parts + footer into one file. bzip2 reads several streams as one.
      def join(output, parts, timestamp)
        header = self.class.compress_to(File.join(@work, "header#{EXT}")) { |out| out.write(header_text(timestamp)) }
        footer = self.class.compress_to(File.join(@work, "footer#{EXT}")) { |out| out.write("</osm>\n") }
        tmp = "#{output}.tmp"
        File.open(tmp, "wb") do |file|
          [header, *parts, footer].each { |part| File.open(part, "rb") { |src| IO.copy_stream(src, file) } }
        end
        FileUtils.mv(tmp, output)
      end

      def header_text(timestamp)
        attrs = Sources::Gpx.new.root_attributes(timestamp)
        open_tag = Builder::XmlMarkup.new(:indent => 2).osm(attrs) { nil }.lines.first
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n#{open_tag}"
      end

      # A forked process that reads traces from a pipe and writes one part.
      class WorkerProcess
        attr_reader :writer

        def initialize(index, work, columns, metadata_path, others)
          name = format("part-%<index>03d", :index => index)
          @part = File.join(work, "#{name}#{EXT}")
          @counts_path = File.join(work, "#{name}.counts")
          reader, @writer = IO.pipe
          Runner.widen(@writer)
          @pid = fork do
            # The pipes of the other workers, or they never see their end of input.
            @writer.close
            others.each { |other| other.writer.close }
            store = Metadata.open(metadata_path)
            Runner.compress_to(@part) do |out|
              counts = Worker.new(store, :columns => columns).run(reader, out)
              File.write(@counts_path, "#{counts[:traces]} #{counts[:skipped]}")
            end
            store.close
            exit!(0) # not the at_exit hooks of the parent
          rescue StandardError => e
            warn "osmrep worker #{index}: #{e.class}: #{e.message}"
            exit!(1)
          end
          reader.close
        end

        def write(text)
          @writer.write(text)
        end

        # Waits for the worker, adds its counts and returns its part.
        def finish(counts)
          @writer.close
          _, status = Process.wait2(@pid)
          raise Error, "worker #{@pid} failed" unless status.success?

          traces, skipped = File.read(@counts_path).split.map { |n| Integer(n) }
          counts[:traces] += traces
          counts[:skipped] += skipped
          @part
        end
      end
    end
  end
end
