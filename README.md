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

they can not combined as of now, only one may be used, the default is to not expire the upload, like before the addition of this feature.

the marker for expiration is simply a file adhering to a naming convention indiciating the unix timestamp of expiry.

a cron container has also been added, it will find expired uploads every 20 minutes and delete them.
