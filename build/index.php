<?php
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
<input type="submit" name="submit" value="go">
</form>
</body></html>
<?php
} else {
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
  if (isset($_REQUEST['exp']) && preg_match('/^(\d+)([hdwmy])$/', $_REQUEST['exp'], $matches) === 1) {
    switch ($matches[2]) {
      case 'h':
        $hours = $matches[1];
        break;
      case 'd':
        $hours = 24 * $matches[1];
        break;
      case 'w':
        $hours = 24 * 7 * $matches[1];
        break;
      case 'm':
        $hours = 24 * 30.5 * $matches[1];
        break;
      case 'y':
        $hours = 24 * 365 * $matches[1];
        break;
    }
    $expiry = time() + ($hours * 60 * 60);
    touch($basedir.'/'.$newdir.'/expires-at-'.$expiry);
  }
  $scheme = $_SERVER['HTTP_X_FORWARDED_PROTO']
         ?? $_SERVER['REQUEST_SCHEME']
         ?? 'https';
  echo $scheme."://".$_SERVER['HTTP_HOST']."/dl/".$newdir."/".$newFName;
  echo "\n";
}
?>
