require 'httpclient'
require 'rufus-scheduler'
require 'yaml'
require 'json'

# get config file
CONFIG = YAML.load_file('config.yml')

WPT_Test_URL = CONFIG['WPT_TestRunner_URL']
WPT_Check_URL = CONFIG['WPT_TestStatus_URL']
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

	clnt = HTTPClient.new
	p "WPT Test Started..."
	@test_started = Time.now.to_i
	@timeout = 600

	post_body = { 'uastring' => 'AAA', 'label' => test_tag,
		       'url' => test_url, 'location' => loc, 'f' => F,
					 'fvonly' => Fview, 'k' => rr_key, 'video' => Cvideo, 'r' => req_id }

	header = { 'Content-Type' => 'application/x-www-form-urlencoded'}

	resp_start = clnt.post(WPT_Test_URL, post_body, header)

  p "Getting the response from WPT Server for requestID: #{req_id} : " + Time.now.to_s
  p parsed = JSON.parse(resp_start.body)
  if parsed['statusCode'] == 200
    test_id = parsed['data']['testId']
  elsif parsed['statusCode'] == 400
  	p parsed['statusText']
	else
		p 'May exceed the daily test limit for the given API key already'
		exit 1
	end

	@scheduler = Rufus::Scheduler.new
	retry_count = 0
	#check testing results until timed out
  @scheduler.every Retry_interval do

    @test_duration = Time.now.to_i - @test_started

    #test timeout default value set to 10 mins
    if @test_duration < @timeout
      p 'checking test status...'
			query = { 'f' => 'json', 'test' => test_id }
      resp_status = clnt.get(WPT_Check_URL, query)
			status_parsed = JSON.parse(resp_status.body)
			test_status_code = status_parsed['statusCode']
			if (test_status_code == 200 || retry_count > Max_retry)
				p status_parsed['statusText']
				p "collecting the testing results..."
				@scheduler.shutdown

			#101 means testing is pending and not started yet..so reset the retry count to 0
			elsif test_status_code == 101
			  retry_count = 0
				p status_parsed['statusText']
				p "will retry in next #{Retry_interval} seconds..."

			else
	      retry_count = retry_count + 1
				p status_parsed['statusText']
				p "will retry in next #{Retry_interval} seconds..."

			end

    else
      p "===Test Timed Out after #{@test_duration} seconds, exiting==="
			p "hanging or queuing?? please check WPT instance if it is working well at this moment..."
      @scheduler.shutdown
			exit 1
    end
  end

  @scheduler.join

  #Post Data to App server
  query = { 'testid' => test_id, 'reqid' => req_id, 'env' => env }
	resp_perfhub = clnt.get(App_URL, query)
	p "testing result has been collected on app server..."
}
