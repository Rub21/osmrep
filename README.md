# osmrep

Replication feeds and dumps for OpenStreetMap tables that
[osmdbt](https://github.com/openstreetmap/osmdbt) does not cover. It starts
with GPS traces and can be extended to other tables.

## Usage

```
osmrep gpx replicate            # one run, for a cron or systemd timer
osmrep gpx dump -o gpx.osm.gz   # full dump
```

`config.yaml`:

```yaml
database: postgres://user:password@host/openstreetmap
data_dir: /var/lib/osmrep
aws_profile: osm-pds-upload       # optional, for the S3 upload
sources:
  gpx:
    limit: 1000     # rows per file, default 10000
    data_dir: /store/planet/replication/gpx         # default: <data_dir>/<source>
    s3_dir: s3://osm-planet-eu-central-1/gpx/replication/minute   # optional
```

With `s3_dir` set, each run copies the new file, its state file and `state.txt`
to S3 with `aws s3 cp`, the same way the minutely and changesets feeds do.

## How a run works

One database transaction:

1. `UPDATE gpx_files SET replicated = true WHERE id IN (... WHERE NOT replicated LIMIT n FOR UPDATE) RETURNING ...`
2. Write the file and `state.txt`, fsync, rename into place.
3. `COMMIT`.

If the process dies before the commit, the flags roll back and the rows go
into the next file. Duplicates are possible, lost rows are not. When nothing is
pending, no file is written.

## Output

```
<data_dir>/gpx/state.txt
<data_dir>/gpx/000/000/001.osm.gz
<data_dir>/gpx/000/000/001.state.txt
```

```xml
<osm version="0.6" generator="osmrep 0.1.0" timestamp="2026-10-13T17:01:21Z">
  <trace id="136" visible="true" visibility="identifiable" timestamp="2026-06-26T15:41:02Z"
         uid="2" user="Rub21" lat="59.9473485" lon="10.7231631" points="1">
    <name>001241927.gpx</name>
    <description>test trace</description>
    <tag v="test"/>
    <trk>
      <trkseg>
        <trkpt lat="59.9473485" lon="10.7231631">
          <ele>182.2</ele>
          <time>2012-05-24T13:27:54Z</time>
        </trkpt>
      </trkseg>
    </trk>
  </trace>
  <trace id="135" visible="false"/>
</osm>
```

Only identifiable traces carry their content: user, name, tags and points with
timestamps. Any other trace is only a header, `<trace id="..." visible="true"
visibility="trackable"/>`, so a consumer can drop a trace that is no longer
identifiable. A deleted trace is `<trace id="..." visible="false"/>`. Trackable
traces can be added later with one constant in the gpx source.

The dump has the same format for every visible identifiable trace, plus
`replication_sequence` on `<osm>`, so a consumer knows where to continue.


## Why Ruby

- The volume is small. A run writes a few thousand points, the worst case
  after a bulk visibility change is a few million, and the `limit` keeps it
  short. There is no performance reason for a compiled language here.
- The dump is I/O bound. The time goes into reading rows from PostgreSQL
  and writing gzip, both done in C by the `pg` and `zlib` libraries. Ruby
  only turns rows into XML.
- It matches the stack. openstreetmap-website and the changesets replication
  are Ruby, so the people who maintain them can maintain this too.
- The current GPS tools are C code without an active maintainer. A rewrite in
  C++ would repeat that problem.

## Development

```
bundle install
bundle exec rake test
bundle exec rubocop
```
