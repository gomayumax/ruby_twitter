require 'sinatra'
require 'sinatra/reloader'
require 'pp'
require 'digest/sha2'
require 'mysql2'

enable :sessions
set :session_secret, '1234'

$client = Mysql2::Client.new(:host => 'localhost', :user => 'root', :password => '', :database=> 'test_bbs')
# DB設定ファイルの読み込み
#ActiveRecord::Base.configurations = YAML.load_file('database.yml')
#ActiveRecord::Base.establish_connection('development')

#class Topic < ActiveRecord::Base
#end

get '/' do
  session.clear
  erb :login
end

post '/login' do
  statement = $client.prepare("select * from users where name = ? and passwd = ?")
  result = statement.execute(params['id'], Digest::SHA256.hexdigest(params['pass']))
  if result.count == 1 then
    result.each do |row|
        session[:id] = row['id']
        session[:name] = row['name']
    end
    @name = session[:name]
    @result = read_postlist
    erb :conect
  else
    @error = 'not find user'
    erb :login
  end
end

get '/new' do
   erb :new
end

post '/new' do
  statement = $client.prepare("insert into users (name,passwd) values ( ?, ?)")
  result = statement.execute(params['id'], Digest::SHA256.hexdigest(params['pass']))
  @message = 'create user'
  erb :new
end

post '/bbs' do
  statement = $client.prepare("insert into postlist (name,textarea,time) values ( ?, ?, now())")
  result = statement.execute(params['name'], params['text'])
  @name = session[:name]
  @result = read_postlist
  erb :conect
end

def read_postlist
  query = %q{select * from postlist}
  $client.query(query)
end
