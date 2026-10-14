# osmrep

Replication feeds and dumps for OpenStreetMap tables that
[osmdbt](https://github.com/openstreetmap/osmdbt) does not cover. It starts
with GPS traces and can be extended to other tables.

## Commands

```
osmrep gpx replicate               # one run: writes the pending traces as one replication file
osmrep gpx dump -o gpx.osm.bz2     # full dump of the traces (.bz2, .gz or plain XML by extension)
```

Options: `-c PATH` config file, default `config.yaml` in the current directory
or `$OSMREP_CONFIG`. `-q` no log. `-v` version.

## Config

`config.yaml`:

```yaml
database: postgres://user:password@host/openstreetmap
data_dir: /var/lib/osmrep           # files go to <data_dir>/gpx/
aws_profile: osm-pds-upload         # optional, for the S3 upload
sources:
  gpx:
    limit: 1000                                   # rows per file, default 10000
    content_visibilities: [identifiable, trackable]   # traces that carry their points, default both
    s3_dir: s3://osm-planet-eu-central-1/gpx/replication/minute   # optional
```

`OSMREP_DATABASE` and `OSMREP_DATA_DIR` override the file. With `s3_dir` set,
each run copies the new file, its state file and `state.txt` to S3 with
`aws s3 cp`, like the minutely and changesets feeds.

## Minute replication

`osmrep gpx replicate` is one run. On a server a systemd timer calls it every
minute, like `replicate-changesets`. Each run is one database transaction:

1. `UPDATE gpx_files SET replicated = true WHERE id IN (... WHERE NOT replicated LIMIT n FOR UPDATE) RETURNING ...`
2. Write the file and `state.txt`, fsync, rename into place.
3. `COMMIT`.

If the process dies before the commit, the flags roll back and the rows go
into the next file. Duplicates are possible, lost rows are not. When nothing is
pending, no file is written.

Output, same layout as `planet.osm.org/replication/`:

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
  <trace id="42" visible="true" visibility="trackable" lat="52.51" lon="13.37" points="791">
    <trk><trkseg><trkpt lat="52.5100000" lon="13.3700000"><time>2022-05-12T02:39:37Z</time></trkpt>...</trkseg></trk>
  </trace>
  <trace id="135" visible="false"/>
</osm>
```

Each `<trace>` is one row of `gpx_files`. The points come from `gpx_tracks`
([openstreetmap-website#7348](https://github.com/openstreetmap/openstreetmap-website/pull/7348)),
in the same GPX layout as the trackpoints API.

- identifiable: user, date, name, description, tags and points
- trackable: points only


## Full dump

```
osmrep gpx dump -o gpx-planet-251014.osm.bz2
```

Same format as the feed, plus `replication_sequence` on `<osm>` so a consumer
knows where to continue. `.osm.bz2` like the planet and notes dumps, with
`pbzip2` when installed. md5, `latest` link and the copy to S3 are the job of
the script that calls it, like `planet-notes-dump`.

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
