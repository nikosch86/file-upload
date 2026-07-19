<?php

// A century. Longer durations overflow the expiry timestamp into a marker cron
// cannot parse, which leaves the upload permanent.
define('MAX_EXPIRY_SECONDS', 100 * 365 * 24 * 60 * 60);

// Parse a duration like "1w" into seconds. Returns false if it does not match.
function parse_duration($spec) {
  if (!is_string($spec) || preg_match('/^(\d+)([hdwmy])$/', $spec, $matches) !== 1) {
    return false;
  }
  $count = (int)$matches[1];
  switch ($matches[2]) {
    case 'h':
      $hours = $count;
      break;
    case 'd':
      $hours = 24 * $count;
      break;
    case 'w':
      $hours = 24 * 7 * $count;
      break;
    case 'm':
      $hours = 24 * 30.5 * $count;
      break;
    case 'y':
      $hours = 24 * 365 * $count;
      break;
  }
  // Compare before casting: an out-of-range float cast is undefined and wraps negative.
  $seconds = $hours * 60 * 60;
  if ($seconds < 1 || $seconds > MAX_EXPIRY_SECONDS) {
    return false;
  }
  return (int)round($seconds);
}

// The deployment-wide fallback, applied only when the request carries no exp.
// null means "never expire", false means the setting itself is unusable.
function default_expiry_seconds() {
  $spec = $_SERVER['DEFAULT_EXPIRY'] ?? getenv('DEFAULT_EXPIRY');
  if ($spec === false || $spec === '') {
    return null;
  }
  return parse_duration($spec);
}

function default_expiry_label() {
  $spec = $_SERVER['DEFAULT_EXPIRY'] ?? getenv('DEFAULT_EXPIRY');
  return ($spec === false || $spec === '') ? 'never' : $spec;
}

if(!isset($_FILES['file'])) {
?>
<!DOCTYPE html>
<html lang="en"><head><meta http-equiv="content-type" content="text/html; charset=UTF-8" /><title>file sharing</title>
<style>
a {
  color: black;
  text-decoration: underline;
}
a:hover {
  color: #666;
}
</style>
</head><body>
<form enctype="multipart/form-data" method="POST">
<input name="file" type="file">
<select name="exp">
<option value="">default (<?php echo htmlspecialchars(default_expiry_label(), ENT_QUOTES); ?>)</option>
<option value="1h">1 hour</option>
<option value="1d">1 day</option>
<option value="1w">1 week</option>
<option value="1m">1 month</option>
<option value="1y">1 year</option>
</select>
<input type="submit" name="submit" value="go">
</form>
</body></html>
<?php
} else {
  // Querystring for curl, form field for the browser. Not $_REQUEST: that also
  // folds in cookies, where a stray exp would reject every upload.
  $exp = $_GET['exp'] ?? $_POST['exp'] ?? null;

  // Resolve the expiry before storing anything, so a bad request leaves no directory behind.
  if ($exp !== null && $exp !== '') {
    $ttl = parse_duration($exp);
    if ($ttl === false) {
      http_response_code(400);
      exit("invalid exp, expected <number><h|d|w|m|y>, for example 1w\n");
    }
  } else {
    $ttl = default_expiry_seconds();
    if ($ttl === false) {
      http_response_code(500);
      exit("server misconfigured: DEFAULT_EXPIRY is not a valid duration\n");
    }
  }

  $newFName = preg_replace('/[^a-z0-9\._\-]/i', '_', $_FILES['file']['name']);
  $newFName = ltrim($newFName, '.');
  if ($newFName === '') {
    $newFName = 'file';
  }
  $basedir = realpath('../dl');
  $newdir = bin2hex(random_bytes(16));
  if (!@mkdir($basedir.'/'.$newdir, 0755)) {
    http_response_code(500);
    exit("upload failed\n");
  }
  if (!move_uploaded_file($_FILES['file']['tmp_name'], $basedir.'/'.$newdir.'/'.$newFName)) {
    @rmdir($basedir.'/'.$newdir);
    http_response_code(500);
    exit("upload failed\n");
  }
  if ($ttl !== null) {
    touch($basedir.'/'.$newdir.'/expires-at-'.(time() + $ttl));
  }
  $scheme = $_SERVER['HTTP_X_FORWARDED_PROTO']
         ?? $_SERVER['REQUEST_SCHEME']
         ?? 'https';
  echo $scheme."://".$_SERVER['HTTP_HOST']."/dl/".$newdir."/".$newFName;
  echo "\n";
}
?>
