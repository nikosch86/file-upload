# file-upload
most simple file upload container  
to be used via curl  
`curl -F file=@somefile https://your-url`

supports expiration by adding `?exp=..` to the querystring, like so:  
`curl -F file=@somefile https://your-url?exp=1w`  

the duration expressions supported are:
* h - hours
* d - days
* w - weeks
* m - months
* y - years

they can not combined as of now, only one may be used.

an `exp` value that does not parse is rejected with `400` and nothing is stored, so a typo can not silently produce a permanent upload. zero durations and anything beyond 100 years are rejected too — an unbounded value overflows the expiry timestamp and produces a marker the cleaner can not read, which would quietly make the upload permanent.

## configuration

| env var | default | meaning |
| --- | --- | --- |
| `DEFAULT_EXPIRY` | unset | expiry applied when the request carries no `exp`, same syntax as `exp`. unset means uploads never expire |
| `TRUSTED_PROXIES` | `192.168.0.0/16` | space separated list of IPs/CIDRs whose `X-Forwarded-For` is believed, for real client IPs in the access log |

both are validated at startup, the container refuses to start on a bad value rather than quietly serving without retention.

`DEFAULT_EXPIRY` is unset by default so an upgrade never silently adds a retention policy. on a public instance you almost certainly want to set it: without it, uploads made through the web form are permanent, since the form only sends `exp` when you pick one.

note that it applies to new uploads only. the expiry marker is written at upload time, so uploads that already exist have no marker and are never touched retroactively — turning `DEFAULT_EXPIRY` on bounds future growth, it does not reclaim what is already on disk.

the marker for expiration is simply a file adhering to a naming convention indiciating the unix timestamp of expiry.

a cron container has also been added, it will find expired uploads every 20 minutes and delete them.

the project is meant to be used behind a reverse proxy, which is not in scope, I personally run a non-docker reverse proxy in front of all my projects, that's why this is bound to localhost by default.  

there are many projects out there incorporating TLS and all kinds of nice features, this one for example: https://github.com/linuxserver/docker-letsencrypt it could easily be added to the compose file and you're good to go
