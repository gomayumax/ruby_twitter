require 'sinatra'
require 'sinatra/reloader'
require 'pp'
require 'digest/sha2'
require 'mysql2'
require 'mysql2-cs-bind'

enable :sessions
set :session_secret, '1234'

$client = Mysql2::Client.new(:host => 'localhost', :user => 'root', :password => '', :database=> 'test_bbs')

# Model
class User
  def login(params)
    statement = $client.prepare("select * from users where name = ? and passwd = ?")
    result = statement.execute(params['id'], Digest::SHA256.hexdigest(params['pass']))
    if result.count == 1 then
      return true, result
    else
      return false, result
    end
  end

  def create(params)
    statement = $client.prepare("insert into users (name,passwd) values ( ?, ?)")
    statement.execute(params['id'], Digest::SHA256.hexdigest(params['pass']))
  end

  def getName(userId)
    statement = $client.prepare("select name from users where id = ?")
    name = ''
    statement.execute(userId).each do |row|
      name = row['name']
    end
    return name
  end

  def follow(toId, fromId, flg)
    pp flg
    if flg == "0" && toId != fromId then
      statement = $client.prepare("select * from follow where del_flg = 1 and to_id = ? and from_id = ?")
      if statement.execute(toId, fromId).count > 0 then
        statement = $client.prepare("update follow set del_flg = NULL where to_id = ? and from_id = ?")
        statement.execute(toId, fromId)
     else
        statement = $client.prepare("insert into follow (to_id,from_id) values ( ?, ?)")
        statement.execute(toId, fromId)
      end
   elsif flg == "1"
     statement = $client.prepare("update follow set del_flg = 1 where to_id = ? and from_id = ?")
     statement.execute(toId, fromId)
   end
  end

  def getFollowList(userId)
    followList = Array.new
    statement = $client.prepare("select u.id, u.name, f.`from_id` from follow as f left join users as u on u.id = f.`to_id` where f.`from_id` = ? and f.`del_flg` is null")
    statement.execute(userId).each do |row|
      followList.push({:id => row['id'], :name => row['name']})
    end
    return followList
  end
end

class Timeline
  def readAll(userId, userObj)
    postData = readPost(userId,userObj)
    postData = readReply(postData,userObj)
    postData = readfollow(userId,postData,userObj)
    tweetData = readFav(userId, postData)
    return tweetData
  end

  def readfollow(userId,postData,userObj)
    followList = userObj.getFollowList(userId)
    followIdList = Array.new
    followList.each do |row|
      followIdList.push(row[:id])
    end
    postData.each do |row|
      val = followIdList.find{|followId| followId == row[1][:user][:id].to_i}
      if val != nil then
        row[1][:user][:follow] = 1
      else
        row[1][:user][:follow] = 0
      end
    end
    postData
  end

  def readFavAll(userId, userObj)
    favData = userfav(userId)
    favData = prepare(favData,userObj)
    tweetData = readReply(favData,userObj)
    tweetData = readFav(userId, tweetData)
    return tweetData
  end

  def prepare(result,userObj)
    data = Hash.new
    result.each do |row|
      pp row
      data[row['id']] = Hash.new
      data[row['id']] = {:user => {:id => row['user_id'], :name => userObj.getName(row['user_id'])}, :text => row['textarea'], :reply => Array.new, :fav => {:flg => '', :num => 0}}
    end
    return data
  end

  def readPost(userId, userObj)
    followList = userObj.getFollowList(userId)
    if followList.empty? then
      query = 'select * from postlist where del_flg is NULL and to_id is NULL and user_id = ? order by time DESC'
      statement = $client.prepare(query)
      result = statement.execute(userId)
    else
      query = 'select * from postlist where del_flg is NULL and to_id is NULL and  user_id in ( ? ) order by time DESC' 
      ids = Array.new
      ids.push(userId)
      followList.each do |follow|
        ids.push(follow[:id])
      end
      result  = $client.xquery(query,ids)
    end
    postData = prepare(result,userObj)
   return postData
  end

  def readReply(postData,userObj)
    query = %q{select * from postlist where del_flg is NULL and to_id is not NULL order by time}
    result = $client.query(query)
    result.each do |row|
      if postData[row['to_id']] then
        postData[row['to_id']][:reply].push({:user => {:id => row['user_id'], :name => userObj.getName(row['user_id'])}, :text => row['textarea'], :id => row['id']})
      end
    end
    return postData
  end

  def post(user_id,text)
    statement = $client.prepare("insert into postlist (user_id,textarea,time) values ( ?, ?, now())")
    statement.execute(user_id, text)
  end

  def reply(userId,text,toId)
    statement = $client.prepare("insert into postlist (user_id,textarea,time,to_id) values ( ?, ?, now(),?)")
    statement.execute(userId,text,toId)
  end

  def addFav( userId, twId, favFlg)
    if favFlg == '' then
      statement = $client.prepare("select * from favlist where del_flg = 1 and user_id = ? and tweet_id = ?")
      if statement.execute(userId, twId).count > 0 then
        statement = $client.prepare("update favlist set del_flg = NULL where user_id = ? and tweet_id = ?")
        statement.execute(userId, twId)
      else
        statement = $client.prepare("insert into favlist (user_id,tweet_id) values ( ?, ?)")
        statement.execute(userId, twId)
      end
    elsif favFlg == "1"
      statement = $client.prepare("update favlist set del_flg = 1 where user_id = ? and tweet_id = ?")
      statement.execute(userId, twId)
    end
  end

  def readFav(userId, tmp)
    favlist = userfav(userId)
    favlist.each do |row|
      if tmp[row['id']] then
      tmp[row['id']][:fav][:flg] = 1
      end
    end
    tmp.each do |key, value|
      tmp[key][:fav][:num] = tweetfavNum(key)
    end
    return tmp
  end

  def userfav(userId)
    statement = $client.prepare("select p.* from favlist as f left join postlist as p on f.tweet_id = p.id where f.del_flg is NULl and f.user_id = ? order by f.updata_date DESC")
    statement.execute(userId)
  end

  def tweetfavNum(twId)
      statement = $client.prepare("select * from favlist where del_flg is NULL and tweet_id = ?")
      statement.execute(twId).count
  end
end

class Header
  def get( title, menu=Array.new)
    headerItem = Hash.new
    headerItem[:title] = title
    headerItem[:menu] = menu 
    return headerItem
  end
end

##############
##Controller##
##############

get '/' do
  session.clear
  header = Header.new
  @header = header.get('Login', [{:name => 'sign in', :url => './new'}])
  erb :login
end

get '/new' do
  header = Header.new
  @header = header.get('Sign in', [{:name => 'Log in', :url => '/'}])
  erb :new
end

post '/new' do
  user = User.new
  header = Header.new
  user.create(params)
  @message = 'create user'
  @header = header.get('Sign in', [{:name => 'Log in', :url => '/'}])
  erb :new
end

post '/login' do
  user = User.new
  result, data = user.login(params)
  if result then
    data.each do |row|
      session[:id] = row['id']
      session[:name] = row['name']
    end
    redirect to('/home')
  else
    @error = 'misss'
    erb :login
  end
end

get '/home' do
  timeline = Timeline.new
  header = Header.new
  userObj = User.new
  @header = header.get('Hello ' + session[:name], [{:name => 'Log out', :url => '/'}])
  @result = timeline.readAll(session[:id],userObj)
  session[:lastpage] = 'home'
  erb :home
end

post '/post' do
  timeline = Timeline.new
  timeline.post(params['user_id'], params['text'])
  redirect to('/' + session[:lastpage])
end

get '/reply' do
  erb :reply
end

post '/reply' do
  timeline = Timeline.new
  timeline.reply(params['user_id'], params['rep_text'],params['to_id'])
  redirect to('/' + session[:lastpage])
end

get '/fav' do
  timeline = Timeline.new
  header = Header.new
  userObj = User.new
  @header = header.get('fav all', [{:name => 'Log out', :url => '/'}])
  @result = timeline.readFavAll(session[:id],userObj)
  session[:lastpage] = 'fav'
  erb :fav
end

post '/fav' do
  timeline = Timeline.new
  timeline.addFav(session[:id], params['tw_id'], params['fav'])
  redirect to('/' + session[:lastpage])
end

post '/follow' do
  user = User.new
  user.follow(params['to_id'].to_i, session[:id], params['follow'])
  redirect to('/' + session[:lastpage])
end

get '/followlist' do
  user = User.new
  header = Header.new
  @List = user.getFollowList(session[:id])
  @header = header.get('Follow List', [{:name => 'Log out', :url => '/'}])
  session[:lastpage] = 'followlist'
  erb :followlist
end
