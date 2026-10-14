# osmrep

Replication feeds and dumps for OpenStreetMap tables that
[osmdbt](https://github.com/openstreetmap/osmdbt) does not cover. It starts
with GPS traces and can be extended to other tables.

## Usage

```
osmrep gpx replicate            # one run, for a cron or systemd timer
osmrep gpx dump -o gpx.osm.bz2  # full dump (.bz2, .gz or plain XML by extension)
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
         uid="2" user="Rub21" lat="59.9473485" lon="10.7231631" points="1204">
    <name>001241927.gpx</name>
    <description>test trace</description>
    <tag v="test"/>
    <trk>
      <trkseg>
        <trkpt lat="59.9473485" lon="10.7231631"><ele>182.2</ele><time>2012-05-24T13:27:54Z</time></trkpt>
        ...
      </trkseg>
    </trk>
  </trace>
  <trace id="135" visible="false"/>
</osm>
```

The points use the same GPX layout as the trackpoints API. They come from the
`gpx_tracks` table
([openstreetmap-website#7348](https://github.com/openstreetmap/openstreetmap-website/pull/7348)),
one `<trkseg>` per row, formatted by PostGIS so Ruby only copies the text.
Only identifiable traces carry their content: user, name,
tags and points. Any other trace is only a header, `<trace id="..." visible="true"
visibility="trackable"/>`, so a consumer can drop a trace that is no longer
identifiable. A deleted trace is `<trace id="..." visible="false"/>`. Trackable
traces can be added later with one constant in the gpx source.

The dump has the same format for every visible identifiable trace, plus
`replication_sequence` on `<osm>`, so a consumer knows where to continue.


## Full dump like planetdump

`script/gpx-dump` does what the planet server does for the map data:
`pg_dump` of the gpx tables into one `.dmp` file, `pg_restore` into an empty
scratch database, `osmrep gpx dump` against that database, then md5, a
`gpx-planet-latest.osm.bz2` link and an optional copy to S3. The dump is
`.osm.bz2` like the planet and notes dumps, with `pbzip2` when it is installed.
The replication files stay `.osm.gz` like the changesets feed. The production
database is only read by `pg_dump`. Settings are environment variables, see the
top of the script. In osm-dev:

```
make up OSMREP=1
docker compose exec -e PGHOST=db -e PGUSER=postgres -e PGPASSWORD=... \
  -e WORK_DIR=/tmp/gpxdump -e PLANET_DIR=/data/gps -e OSMREP_DATA_DIR=/data \
  -e OSMREP="bundle exec bin/osmrep" osmrep bash script/gpx-dump
```

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
