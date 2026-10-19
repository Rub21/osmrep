# osmrep

Minute replication feed of the OpenStreetMap GPS traces.

## Commands

```sh
osmrep gpx replicate                            # write the pending traces as one replication file
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

## Why Ruby

- The feed is small: a few thousand points per minute.
- openstreetmap-website is Ruby, so the same people can maintain this.

## Development

```
bundle install
bundle exec rake test
bundle exec rubocop
```
