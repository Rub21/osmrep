# osmrep

Replication feed and full dump of the OpenStreetMap GPS traces.

## Commands

```sh
osmrep gpx replicate                            # write the pending traces as one replication file
osmrep gpx dump --from gpx.dmp -o gpx.osm.bz2   # full dump from a pg_dump file
```

`-c PATH` config file, default `config.yaml` or `$OSMREP_CONFIG`. `-q` no log.

## Config

```yaml
database: postgres://user:password@host/openstreetmap
data_dir: /var/lib/osmrep           # files go to <data_dir>/gpx/
aws_profile: osm-pds-upload         # optional, for the S3 upload
sources:
  gpx:
    limit: 1000                                       # rows per file, default 10000
    content_visibilities: [identifiable, trackable]   # traces that carry their points, default both
    s3_dir: s3://osm-planet-eu-central-1/gpx/replication/minute   # optional
```

`OSMREP_DATABASE` and `OSMREP_DATA_DIR` override the file. With `s3_dir`,
each new file goes to S3 with `aws s3 cp`.

## Minute replication

`osmrep gpx replicate` is one run; a systemd timer calls it every minute. One
transaction: mark the pending rows (`UPDATE gpx_files SET replicated = true
... RETURNING`), write the file and `state.txt`, commit. If the run dies
before the commit, the rows go into the next file. Nothing is written when
nothing is pending.

Same layout as `planet.osm.org/replication/`:

```
<data_dir>/gpx/state.txt
<data_dir>/gpx/000/000/001.osm.gz
<data_dir>/gpx/000/000/001.state.txt
```

## Full dump

Two steps, like the planet dump: `pg_dump` writes the four tables to a file,
then osmrep reads that file and writes the XML. Only `pg_dump` touches the
database.

```sh
pg_dump --format=custom --data-only --table=gpx_files --table=gpx_file_tags --table=gpx_tracks --table=users --file=gpx.dmp openstreetmap
osmrep gpx dump --from gpx.dmp -o gpx-planet-251014.osm.bz2 --jobs 8
```

- `--from` the pg_dump file, custom format or plain SQL.
- `--jobs` worker processes, default 4. `--work-dir` for temporary files,
  default the directory of the output.

Same XML as the feed, `.osm.bz2`. The `timestamp` of `<osm>` is when
`pg_dump` ran, so a consumer knows from where to follow the feed. How it works: the small tables go into a
SQLite file, then `gpx_tracks` is read once and each trace goes to a worker
when all its rows came. The rows of a trace are usually together in the file,
so little is held in memory; when the open traces pass 1 GB they go to a
file that is sorted and written at the end.

## Why Ruby

- The feed is small: a few thousand points per minute.
- The dump reads a `pg_dump` file; `pg_restore`, `sort` and `bzip2` do the
  heavy work. Ruby decodes the points in worker processes. If that is too slow
  on the full table, `Dump::Worker` can be replaced by a small compiled
  program while the rest stays in Ruby.
- openstreetmap-website is Ruby, so the same people can maintain this.

## Development

```
bundle install
bundle exec rake test
bundle exec rubocop
```
