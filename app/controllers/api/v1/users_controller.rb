
require_relative 'error'

require 'securerandom'
require 'digest'

class Api::V1::UsersController < Api::V1::BaseController 
	def count
		render(json: { :users => { :count => User.count }})
	end

	def show_by_id
		user = User.find(params[:id])
		render(json: user)
	end

	def show_by_username
		user = User.find_by_username(params[:name])

		render(json: user) unless user.nil?
		render(json: Api::V1::Error::record_not_found(params)) if user.nil?
	end

	def index
		users = User.all
		render(json: { :users => users })
	end

	def register	# USERNAME, PASSWORD, FIRST_NAME, LAST_NAME, ADDRESS, EMAIL
		first_name = params[:first_name]
		last_name = params[:last_name]
		username = params[:username]
		password = params[:password]
		address = params[:address]
		email = params[:email]
		
		user = User.new do |user|
			user.first_name = first_name
			user.last_name = last_name
			user.username = usersname
			user.address = address
			user.email = first_name
		end

		unless user.id.nil?	# we have some id, we're ok
			# create a username-password salted token for this username and password
			username_password_salted_token = Digest::SHA1.new.hexdigest "#{username} using: #{password}"

			# create a random unique mail token and send it away
			unique_mail_token = Digest::SHA1.new.hexdigest SecureRandom.uuid

			# set unique_mail_token => mail::username_password_salted_token,id
			$redis.set "claim::#{unique_mail_token}", "mail::#{username_password_salted_token},#{user.id}"

			# make url and send unique mail token away
			render(json: { :mail_url => "#{request.protocol + request.host_with_port}/claim/#{unique_mail_token}"})
		else 
			render(json: Api::V1::Error::username_already_in_use(params))
		end
	end

	def claim	# TOKEN
		unique_mail_token = params[:token]

		# check redis for the claim::unique_mail_token value
		username_password_salted_token_and_id = $redis.get "claim::#{unique_mail_token}"

		unless username_password_salted_token_and_id.nil?
			# extract the salted token and id
			username_password_salted_token, id = username_password_salted_token_and_id.gsub("mail::", "").split(",")

			# set auth::username_password_salted_token => id
			$redis.set "auth::#{username_password_salted_token}", id

			render(json: { :claimed => 'OK' })
		else
			render(json: { :claimed => Api::V1::Error::token_not_correct(params) })
		end
	end

	def login	# USERNAME PASSWORD
		username = params[:username]
		password = params[:password]

		# create a username-password salted token for this username and password
		username_password_salted_token = Digest::SHA1.new.hexdigest "#{username} using: #{password}"
		id = $redis.get "auth::#{username_password_salted_token}"

		unless id.nil?
			# is there a running session for this user?
			current_session_token = $redis.get "token::#{id}"

			if current_session_token.nil?
				# create a expiring session token
				expiring_session_token = Digest::SHA1.new.hexdigest SecureRandom.uuid

				# set session::expiring_session_token => id
				$redis.set "session::#{expiring_session_token}", id
				$redis.expire "session::#{expiring_session_token}", 3600

				# set token::id => expiring_session_token
				$redis.set "token::#{id}", expiring_session_token
				$redis.expire "session::#{expiring_session_token}", 3600

				render(json: { :session => expiring_session_token })
			else
				render(json: { :session => current_session_token })
			end
		else
			render(json: Api::V1::Error::user_does_not_exist(params))
		end
	end

	def authenticate	# TOKEN
		auth_token = params[:token]

		# try getting the id from the token
		try_to_fetch_id = $redis.get "session::#{auth_token}"

		if try_to_fetch_id.nil?
			return { :auth => Api::V1::Error::could_not_authenticate(params) }
		else
			test_auth_token = $redis.get "token::#{try_to_fetch_id}"

			if test_auth_token.nil?
				return { :auth => Api::V1::Error::could_not_authenticate(params) }
			else 
				return { :auth => true }
			end
		end
	end

	def logout # TOKEN
		auth_token = params[:token]
		try_to_auth = authenticate auth_token

		if try_to_auth[:auth] == true
			$redis.del "session::#{auth_token}"

			render(json: { :logout => true })
		else
			render(json: try_to_auth[:auth][:error])
		end
	end
end