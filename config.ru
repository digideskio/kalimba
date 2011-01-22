require 'kalimba'
dbconfig = YAML.load(File.read('config/database.yml'))
environment = ENV['DATABASE_URL'] ? 'production' : 'development'
Kalimba::Models::Base.establish_connection dbconfig[environment]
Kalimba.create
run Kalimba
