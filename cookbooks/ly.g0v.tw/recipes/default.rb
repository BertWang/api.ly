include_recipe "runit"
include_recipe "database"
include_recipe "postgresql::ruby"

directory "/opt/ly" do
  action :create
end

git "/opt/ly/twlyparser" do
  repository "git://github.com/g0v/twlyparser.git"
  reference "master"
  action :sync
end

execute "install LiveScript" do
  command "npm i -g LiveScript@1.1.1"
  not_if "test -e /usr/bin/lsc"
end

execute "install twlyparser" do
  cwd "/opt/ly/twlyparser"
  action :nothing
  subscribes :run, resources(:git => "/opt/ly/twlyparser")
  command "npm i && sudo npm link"
end


postgresql_connection_info = {:host => "127.0.0.1",
                              :port => node['postgresql']['config']['port'],
                              :username => 'postgres',
                              :password => node['postgresql']['password']['postgres']}

database 'ly' do
  connection postgresql_connection_info
  provider Chef::Provider::Database::Postgresql
  action :create
end

db_user = postgresql_database_user 'ly' do
  connection postgresql_connection_info
  database_name 'ly'
  password 'password'
  privileges [:all]
end

db_user.run_action(:create)

if db_user.updated_by_last_action?

  remote_file "/tmp/api.ly.bz2" do
    source "https://dl.dropboxusercontent.com/u/30657009/ly/api.ly.bz2"
  end

  bash 'extract api.ly' do
    cwd ::File.dirname('/tmp/api.ly.sql')
    code <<-EOH
      bzcat /tmp/api.ly.bz2 > /tmp/api.ly.sql
      EOH
    not_if { ::File.exists?('/tmp/api.ly.sql') }
  end

  postgresql_database "grant schema" do
    connection postgresql_connection_info
    database_name 'ly'
    sql "grant CREATE on database ly to ly"
    action :query
  end

  # XXX: use whitelist
  postgresql_database "plv8" do
    connection postgresql_connection_info
    database_name 'ly'
    sql "create extension plv8"
    action :query
  end

  bash 'init db' do
    connection_info = postgresql_connection_info.clone()
    connection_info[:username] = 'ly'
    connection_info[:password] = 'password'
    conn = "postgres://#{connection_info[:username]}:#{connection_info[:password]}@#{connection_info[:host]}/ly"
    code <<-EOH
      bzcat /tmp/api.ly.bz2 | psql #{conn}
    EOH
  end

#  postgresql_database "init" do
#    connection postgresql_connection_info
#    database_name 'ly'
#    sql { ::File.open("/tmp/api.ly.sql").read }
#    action :query
#  end

end


# XXX: when used with vagrant, use /vagrant_git as source
git "/opt/ly/api.ly" do
  repository "git://github.com/g0v/api.ly.git"
  reference "master"
  action :sync
end

execute "install api.ly" do
  cwd "/opt/ly/api.ly"
  action :nothing
  subscribes :run, resources(:git => "/opt/ly/api.ly")
  command "sudo npm link twlyparser pgrest && npm i && npm run prepublish"
  notifies :restart, "service[lyapi]", :immediately
end

runit_service "lyapi" do
  default_logger true
  action :enable
end

