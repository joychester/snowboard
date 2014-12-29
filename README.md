Snowboard project:

This is helping you to make your own automated page test from public Webpagetest.org(Synthetic Front-End Performance Test)
you can request your own API key from : http://www.webpagetest.org/getkey.php

Usage:
    precondition: check out this repo into your local machine, ruy 2.1 is already tested on windows and Mac OS 10.9; 
    bundle install  -- make sure your bundler is installed; 
    ruby wpt_client.rb -- to get and upload the json objects for your test results; 

PS: you can write your own dashboard or store the whole thing to mongoDB for page trending and further analysis, checkout Page_Trend_WPT images and get some idea of it.