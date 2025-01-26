<?php

define( 'DB_NAME', 'wordpress' );
define( 'DB_USER', 'admin' );
define( 'DB_PASSWORD', 'StrongPassword123!' );
define( 'DB_HOST', 'slengpack-db-instance.cf4amqa86ky4.eu-central-1.rds.amazonaws.com:3306' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );
define( 'WP_HOME', 'https://slengpack.click' );
define( 'WP_SITEURL', 'https://slengpack.click' );
define( 'FORCE_SSL_ADMIN', true );

// Якщо WordPress працює за проксі-сервером чи балансувальником навантаження
if (strpos($_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false) {
$_SERVER['HTTPS'] = 'on';
}

$table_prefix = 'wp_';

define( 'WP_DEBUG', false );

/* That's all, stop editing! Happy blogging. */

if ( !defined('ABSPATH') )
define('ABSPATH', dirname(__FILE__) . '/');

require_once(ABSPATH . 'wp-settings.php');
