require 'sinatra'
require 'sinatra/reloader'

require 'mysql2'
$client = Mysql2::Client.new(:host => 'localhost', :user => 'root', :password => '', :database=> 'test_bbs')
# DB設定ファイルの読み込み
#ActiveRecord::Base.configurations = YAML.load_file('database.yml')
#ActiveRecord::Base.establish_connection('development')

#class Topic < ActiveRecord::Base
#end

get '/' do
  @result = read_postlist
   erb :conect
end

post '/' do
  statement = $client.prepare("insert into postlist (name,textarea,time) values ( ?, ?, now())")
  result = statement.execute(params['name'], params['text'])
  @result = read_postlist
  erb :conect
end

def read_postlist
  query = %q{select * from postlist}
  $client.query(query)
end
