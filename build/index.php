<?php
ini_set('upload_max_filesize', '9G');
ini_set('post_max_size', '10G');
ini_set('memory_limit', '10G');
ini_set('max_input_time', 0);
ini_set('max_execution_time', 0);
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
	if (stristr($_SERVER['HTTP_USER_AGENT'], 'curl')) {
                echo "https://".$_SERVER['HTTP_HOST']."/dl/".$newdir."/".$newFName;
        } else {
		echo "https://".$_SERVER['HTTP_HOST']."/dl/".$newdir."/".$newFName;
		echo "\n";
	}
}
#print_r($_FILES);
?>
