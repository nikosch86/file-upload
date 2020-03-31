<?php
if(!isset($_FILES['file'])) {
?>
<html><head><meta http-equiv="content-type" content="text/html; charset=UTF-8" /><title>file sharing</title>
<style type="text/css">
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
	$basedir = realpath('../dl');
	$newdir = substr(md5(uniqid()), 0, 12);
	exec('mkdir '.$basedir.'/'.$newdir);
	exec('mv '.$_FILES['file']['tmp_name'].' '.$basedir.'/'.$newdir.'/'.$newFName);
        if (isset($_REQUEST['exp'])) {
          preg_match('/^(\d+)([hdwmy]?)$/', $_REQUEST['exp'], $matches);
          if ($matches[1] && $matches[2]) {
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
            $expiry = mktime() + ($hours * 60 * 60);
            exec('touch '.$basedir.'/'.$newdir.'/expires-at-'.$expiry);
          }
        }
	if (stristr($_SERVER['HTTP_USER_AGENT'], 'curl')) {
                echo "https://".$_SERVER['HTTP_HOST']."/dl/".$newdir."/".$newFName;
		echo "\n";
        } else {
		echo "https://".$_SERVER['HTTP_HOST']."/dl/".$newdir."/".$newFName;
		echo "\n";
	}
}
#print_r($_FILES);
?>
