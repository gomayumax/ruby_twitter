require 'sinatra'
require 'sinatra/reloader'

get '/' do
    'hello world'
end

get '/path/' do
    'hello world next'
end

get '/hello/*' do |name|
    "hello #{name}. how are you?"
end

get '/erb_template_page' do
  erb :erb_template_page
end

get '/markdown_template_page' do
    markdown :markdown_template_page
end

get '/erb_and_md_template_page' do
    erb :erb_and_md_template_page
end 
