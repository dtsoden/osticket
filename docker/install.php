<?php
/*
 * Headless osTicket installer.
 *
 * Sets up the same environment as setup/install.php and calls
 * Installer::install() with values taken from environment variables.
 * The entrypoint runs this once, as www-data, when no installed config exists.
 */

if (PHP_SAPI !== 'cli') {
    exit(1);
}

function env($name, $default = '') {
    $value = getenv($name);
    return ($value === false || $value === '') ? $default : $value;
}

$root = '/var/www/html';
$configFile = $root.'/include/ost-config.php';

// setup.inc.php builds the URL constant (stored as the helpdesk URL) from these.
$url = parse_url(rtrim(env('INSTALL_URL', 'http://localhost'), '/'));
if (!$url || empty($url['host'])) {
    fwrite(STDERR, "INSTALL_URL is not a valid URL\n");
    exit(1);
}
if (($url['scheme'] ?? 'http') === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
$_SERVER['HTTP_HOST'] = $url['host'].(isset($url['port']) ? ':'.$url['port'] : '');
$_SERVER['PHP_SELF'] = ($url['path'] ?? '').'/setup/install.php';
$_SERVER['SCRIPT_NAME'] = $_SERVER['PHP_SELF'];
$_SERVER['REMOTE_ADDR'] = '127.0.0.1';
$_SERVER['REQUEST_METHOD'] = 'GET';

// The installer fills %CONFIG-SIRI with a random salt. Writing INSTALL_SECRET
// in first makes the config keep the supplied value instead.
if (env('INSTALL_SECRET')) {
    define('SECRET_SALT', env('INSTALL_SECRET'));
    $sample = file_get_contents($configFile);
    file_put_contents($configFile,
        str_replace('%CONFIG-SIRI', addcslashes(env('INSTALL_SECRET'), "'\\"), $sample));
}

chdir($root.'/setup');
require $root.'/setup/setup.inc.php';
require_once INC_DIR.'class.installer.php';

$installer = new Installer($configFile);
if (!$installer->check_prereq()) {
    fwrite(STDERR, "PHP or MySQL extension requirements not met\n");
    exit(1);
}
if (!$installer->check_config()) {
    fwrite(STDERR, "$configFile is missing or not writable\n");
    exit(1);
}

$vars = array(
    'name'        => env('INSTALL_NAME', 'osTicket Helpdesk'),
    'email'       => env('INSTALL_EMAIL'),
    'fname'       => env('ADMIN_FIRSTNAME'),
    'lname'       => env('ADMIN_LASTNAME'),
    'admin_email' => env('ADMIN_EMAIL'),
    'username'    => env('ADMIN_USER'),
    'passwd'      => env('ADMIN_PASS'),
    'passwd2'     => env('ADMIN_PASS'),
    'prefix'      => env('DB_PREFIX', 'ost_'),
    'dbhost'      => env('DB_HOST'),
    'dbname'      => env('DB_NAME', 'osticket'),
    'dbuser'      => env('DB_USER'),
    'dbpass'      => env('DB_PASS'),
    'timezone'    => env('TIMEZONE', 'UTC'),
    'lang_id'     => env('INSTALL_LANGUAGE', 'en_US'),
);

if (!$installer->install($vars)) {
    fwrite(STDERR, "osTicket install failed:\n");
    foreach ($installer->getErrors() as $field => $error) {
        fwrite(STDERR, sprintf("  %s: %s\n", $field, strip_tags($error)));
    }
    exit(1);
}

echo "osTicket installed. Staff panel: ".URL."scp/\n";
