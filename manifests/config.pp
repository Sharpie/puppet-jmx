# Manage JMX configuration for a Java service
#
# This type manages JMX configuration for Java daemons running on RedHat
# platforms. At the basic level, this type can ensure whether JMX is
# configured and which ports and interface the service listens on.
# Authentication can optionally be configured to use a combination of
# passwords, RBAC and SSL keys.
#
# @param title [String] The name of the service for which JMX configuration
#   should be managed. This should be the title of a Service resource that
#   can be notified when JMX configuration changes.
#
# @param ensure Determines whether to add or remove JMX configuration.
#
# @param env_file A path to the file read by the service manager to set
#   environment variables for the JAVA service.
#
# @param env_java_args The name of a variable used to pass Java command line
#   arguments to processes started by the service manager.
#
# @param config_dir The directory where configuration files related to the
#   service are stored. A `jmx` sub-directory will be created under this
#   location.
#
# @param service_user The user account which should own configuration files
#   related to the service.
#
define jmx::config (
  Enum['present', 'absent'] $ensure = 'present',
  String $env_file = "/etc/sysconfig/${title}",
  String $java_args_var = 'JAVA_ARGS',
  String $config_dir = "/etc/${title}",
  String $service_user = $title,
  Optional[Integer[0]] $port = undef,
  Optional[String] $rmi_hostname = undef,
  Optional[Integer[0]] $rmi_port = undef,
  Boolean $local_only = true,
  Hash $properties = {},
  Hash $users = {},
  Hash $roles = {},
  Hash $keypair = {},
  Array[String] $client_certs = [],
) {

  case $ensure {
    'present': {
      $_dir_ensure = 'directory'
      $_file_ensure = 'file'
    }
    'absent': {
      $_dir_ensure = 'absent'
      $_file_ensure = 'absent'
    }
  }

  # Configure JAVA_ARGS

  ini_subsetting {"${title}: JMX enabled":
    ensure            => $ensure,
    path              => $env_file,
    section           => '',
    setting           => $java_args_var,
    key_val_separator => '=',
    quote_char        => '"',
    subsetting        => '-Dcom.sun.management.jmxremote',
    value             => '',
    notify            => [Service[$title]],
  }

  ini_subsetting {"${title}: JMX config location":
    ensure            => $ensure,
    path              => $env_file,
    section           => '',
    setting           => $java_args_var,
    key_val_separator => '=',
    quote_char        => '"',
    subsetting        => '-Dcom.sun.management.config.file=',
    value             => "${config_dir}/management.properties",
    notify            => [Service[$title]],
  }

  unless ($rmi_hostname =~ Undef) {
    ini_subsetting {"${title}: JMX RMI hostname":
      ensure            => $ensure,
      path              => $env_file,
      section           => '',
      setting           => $java_args_var,
      key_val_separator => '=',
      quote_char        => '"',
      subsetting        => '-Djava.rmi.server.hostname=',
      value             => $rmi_hostname,
      notify            => [Service[$title]],
    }
  }

  file {$config_dir:
    ensure => $_dir_ensure,
    owner  => $service_user,
    mode   => '0700',
  }

  # Configure role based access

  if empty($users) {
    $_user_config = {
      'com.sun.management.jmxremote.authenticate' => false,
    }
  } else {
    $_user_config = {
      'com.sun.management.jmxremote.authenticate'  => true,
      'com.sun.management.jmxremote.password.file' => "${config_dir}/jmxremote.password"
    }
  }

  file {"${config_dir}/jmxremote.password":
    ensure  => $_file_ensure,
    owner   => $service_user,
    mode    => '0600',
    content => template('jmx/jmxremote.password.erb'),
    notify => [Service[$title]],
  }

  if empty($roles) {
    $_role_config = { }
  } else {
    $_role_config = {
      'com.sun.management.jmxremote.access.file' => "${config_dir}/jmxremote.access"
    }
  }

  file {"${config_dir}/jmxremote.access":
    ensure  => $_file_ensure,
    owner   => $service_user,
    mode    => '0600',
    content => template('jmx/jmxremote.access.erb'),
    notify => [Service[$title]],
  }


  # Configure SSL

  Java_ks {
    path => ['/opt/puppetlabs/puppet/bin', '/opt/puppetlabs/server/bin', $::facts['path']]
  }

  if empty($keypair) {
    $_keystore_config = {}
    $_ssl_config = {
      'com.sun.management.jmxremote.ssl' => false,
      'com.sun.management.jmxremote.registry.ssl' => false,
    }
  } else {
    $_keystore_config = {
      'javax.net.ssl.keyStore' => "${config_dir}/jmx.ks",
      'javax.net.ssl.keyStorePassword' => 'puppet',
    }
    $_ssl_config = {
      'com.sun.management.jmxremote.ssl'                    => true,
      'com.sun.management.jmxremote.registry.ssl'           => true,
      'com.sun.management.jmxremote.ssl.enabled.protocols'  => 'TLSv1,TLSv1.1,TLSv1.2',
    }

    java_ks {"${title}:${config_dir}/jmx.ks":
      ensure      => 'latest',
      password    => 'puppet',
      certificate => $keypair['cert'],
      private_key => $keypair['key'],
      require     => File["${config_dir}/jmx.ks"],
      notify      => [Service[$title]],
    }
  }

  if empty($client_certs) {
    $_truststore_config = {}
    $_ssl_auth_config = {
      'com.sun.management.jmxremote.ssl.need.client.auth' => false,
    }
  } else {
    $_truststore_config = {
      'javax.net.ssl.trustStore' => "${config_dir}/jmx.ts",
      'javax.net.ssl.trustStorePassword' => 'puppet',
    }
    $_ssl_auth_config = {
      'com.sun.management.jmxremote.ssl.need.client.auth' => true,
    }
  }

  if empty($keypair) and empty($client_certs) {
    $_ssl_config_file = { }
  } else {
    $_ssl_config_file = {
      'com.sun.management.jmxremote.ssl.config.file' => "${config_dir}/ssl.properties"
    }
  }

  file {"${config_dir}/ssl.properties":
    ensure  => $_file_ensure,
    owner   => $service_user,
    mode    => '0600',
    content => template('jmx/ssl.properties.erb'),
    notify => [Service[$title]],
  }

  file {["${config_dir}/jmx.ks", "${config_dir}/jmx.ts"]:
    ensure  => $_file_ensure,
    owner   => $service_user,
    mode    => '0600',
    notify => [Service[$title]],
  }


  # Set up Base Configuration

  file {"${config_dir}/management.properties":
    ensure  => $_file_ensure,
    owner   => $service_user,
    mode    => '0600',
    content => template('jmx/management.properties.erb'),
    notify => [Service[$title]],
  }

}
