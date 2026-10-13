# frozen_string_literal: true

module Osmrep
  # The directory of one replication feed: state.txt at the top and the
  # files in the 000/000/000 layout. Files are written to a temporary name,
  # synced to disk and then renamed, so a reader never sees a partial file.
  class ReplicationDir
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def state_path
      File.join(path, "state.txt")
    end

    def state
      State.read(state_path)
    end

    def data_path(sequence)
      "#{stem(sequence)}.osm.gz"
    end

    def state_path_for(sequence)
      "#{stem(sequence)}.state.txt"
    end

    def stem(sequence)
      File.join(path, format("%<a>03d/%<b>03d/%<c>03d", :a => sequence / 1_000_000, :b => (sequence / 1000) % 1000, :c => sequence % 1000))
    end

    # Writes the gzipped data file and both state files for the given
    # state. The block receives the gzip stream and writes the content.
    def write(new_state, &)
      data_file = data_path(new_state.sequence)
      tmp_data = "#{data_file}.tmp"
      tmp_state = "#{state_path}.tmp"

      FileUtils.mkdir_p(File.dirname(data_file))
      Zlib::GzipWriter.open(tmp_data, &)
      File.write(tmp_state, new_state.to_s)

      fsync(tmp_data)
      fsync(tmp_state)
      fdirsync(File.dirname(tmp_data))
      fdirsync(File.dirname(tmp_state))

      raise Error, "temporary data file is empty" if File.empty?(tmp_data)

      FileUtils.mv(tmp_data, data_file)
      FileUtils.cp(tmp_state, state_path_for(new_state.sequence))
      FileUtils.mv(tmp_state, state_path)

      fsync(data_file)
      fsync(state_path_for(new_state.sequence))
      fsync(state_path)
      fdirsync(File.dirname(data_file))
      fdirsync(path)

      data_file
    end

    private

    def fsync(file)
      File.open(file, &:fsync)
    end

    def fdirsync(dir)
      dir = File.expand_path(dir)
      while dir != "/"
        File.open(dir, &:fsync)
        dir = File.dirname(dir)
      end
    end
  end
end
