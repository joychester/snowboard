require 'bundler'

Bundler.require

require 'yaml'

# get config file
CONFIG = YAML.load_file('config.yml')

# WPT_URL = CONFIG['WPT_URL']
# Result_Status_URL = CONFIG['WPT_Status_URL']
App_URL = CONFIG['APP_URL']
API_Key = CONFIG['API_KEY']
if API_Key.class == Array
	key_num = API_Key.size
else 
	p "Not well defined API_KEYs in config.yml, should be an array instead of #{API_Key.class}"
	exit 1
end

F = CONFIG['Res_Format']
Fview = CONFIG['firstview_only']
Cvideo = CONFIG['video_cap']
Retry_interval = CONFIG['retry_interval']
Max_retry = CONFIG['max_retry']


#generating random request id
def rand_num(len)
	rand_str = ""
	len.times {
		rand_str << Random.new.rand(9).to_s
	}
	rand_str.to_i
end

# loop all the URLs need to be tested
test_url_hash = CONFIG['Target_URLs_Hash']
round_num = test_url_hash.size

test_url_hash.each { |test_tag, test_info|
	# round robin keys
	p rr_key = API_Key[round_num%key_num]
	round_num = round_num - 1
	
	p "----------Now we are testing " + test_tag + " -----------"
	p test_url = test_info['url']
	loc = test_info['loc']
  	env = test_info['env']
	req_id = rand_num(6)

  # -------
  if env=='production'
    wpt_dn=CONFIG['WPT_PUBLIC_DN']
  else
    wpt_dn=CONFIG['WPT_PRIVATE_DN']
  end

	EM.run do

		conn_options = {
			:connect_timeout => 5,
			:inactivity_timeout => 60
		}

		request_options = {
			:redirects => 3,
			:keepalive => true,
			:head => {
				#specify the correct encoding headers such that the upstream servers knows how to parse your data
				'Content-Type' => 'application/x-www-form-urlencoded'
			},

			:body => "label=#{test_tag}&url=#{test_url}&location=#{loc}&f=#{F}&fvonly=#{Fview}&k=#{rr_key}&video=#{Cvideo}&r=#{req_id}"
		}
		# making the WPT call to kick off the tests
		start_time = Time.now
		conn = EM::HttpRequest.new(wpt_dn+'runtest.php', conn_options)
		http = conn.post request_options
		p "sending the request for requestID: #{req_id}:" + Time.now.to_s

		http.errback{ 
			p "can not make the Http call to WPT public instance"
			EM.stop
		}

		http.callback do
			retry_count = 0
			p "got the response for requestID: #{req_id}:" + Time.now.to_s
			p http.req
			wpt_res_body = http.response
			p parsed = JSON.parse(wpt_res_body)
			if parsed['statusCode'] == 200
				test_id = parsed['data']['testId']
				p "checking the testing status..."
			else
				p 'Invalid Key or exceed the daily test limit for the given key'
				EM.stop
			end

			#Making the GET method call to check test status
			EM.add_periodic_timer(Retry_interval) do
				duration = Time.now - start_time
				if duration > 600
					p "Testing Timed out for over 10 mins, please check WPT instance if it is working well at this moment"
					EM.stop
				end

				stat_conn = EM::HttpRequest.new(wpt_dn+'testStatus.php', conn_options)
				stat_http = stat_conn.get :query => "f=json&test=#{test_id}", :keepalive => true

				stat_http.errback { p "can not get the testing status for id: #{test_id}"; EM.stop}

				stat_http.callback do
					stat_res_body = stat_http.response
					stat_parsed = JSON.parse(stat_res_body)
					stat_id = stat_parsed['statusCode']
					if(stat_id == 200 || retry_count > Max_retry)
						p stat_parsed['statusText']
						p "collecting the testing results..."
						#passing test_id, request_id to app server
						app_conn = EM::HttpRequest.new(App_URL, conn_options)
						app_http = app_conn.post :query => "testid=#{test_id}&reqid=#{req_id}&env=#{env}", :keepalive => true
						app_http.errback do
							p "can not make request to the app server, please double check..."
							EM.stop
						end
						app_http.callback do
							p "testing result has been collected..."
							EM.stop
						end
					elsif (stat_id == 101)
						#101 means testing is pending and not started yet..so reset the retry count to 0
						retry_count = 0
						p stat_parsed['statusText']
						p "will retry in next #{Retry_interval} seconds..."
					else
						retry_count = retry_count+1
						p stat_parsed['statusText']
						p "will retry in next #{Retry_interval} seconds..."
					end
				end
			end
		end
	end
}