#rights=ADMIN
#--------------------------------------------------------------------
#
#This is a GreasySpoon script.
#
#To install, you need :
#   -jruby
#   -hpricot library
#--------------------------------------------------------------------
#
#WHAT IT DOES:
#
#http://www.google.fr:
#   - show ref links as html tag
#
#--------------------------------------------------------------------
#
#==ServerScript==
#@status on
#@name            APG_Nokogiri_ruby
#@order 0
#@description     APG_Nokogiri_ruby
#@include       .*
#==/ServerScript==
#
require 'rubygems'
require 'nokogiri'
require 'digest/md5'
require 'net/http'
require 'uri'
require 'pp'
require 'open-uri'

#Available elements provided through ICAP server
#puts "---------------"
#puts "HTTP request header: #{$requestheader}"
#puts "HTTP request body: #{$httprequest}"
#puts "HTTP response header: #{$responseheader}"
#puts "HTTP response body: #{$httpresponse}"
#puts "user id (login in most cases): #{$user_id}"
#puts "user name (CN  provided through LDAP): #{$user_name}"
#puts "---------------"

def process(httpresponse, url, host, whitelist)
	#puts url
	puts host
	#escape checks
	if host =~ /sample\.in\.unknown/
		return
	end
	#dummy_html = Net::HTTP.get(URI.parse(url))
	p url
	dummy_document = Nokogiri::HTML(open(URI.parse(url)))
	p whitelist
	original_document = Nokogiri::HTML(httpresponse)
	#p dummy_html.to_html
	#Let's have some exceptions defined.
	exceptions = Array.new()
	if (File.exists?("#{whitelist}"))
		file = File.new("#{whitelist}", "r")
		while (line = file.gets)
			#puts line
			exceptions.push(line)
		end
	end
	#outputfile = File.new("#{whitelist}output", "a+")
	#outputfile.syswrite("Begin to parse "+url+"\n")
	#puts "Begin to parse "+url
	numberofscripts = 0
	totalpubliclength = 0
	totalnodecount = 0
	totalpublicnodecount=0
	totallength=0
	untrustedscripts = Array.new()
=begin
	documentOutput = File.new(whitelist+"_doc",'w')
	documentDoutput = File.new(whitelist+"_Ddoc",'w')
	documentOutput.syswrite(original_document.to_html)
	documentDoutput.syswrite(dummy_document.to_html)
	documentOutput.close()
	documentDoutput.close()
=end
	#puts "begin finding 3rd-p scripts"
	#for each 'script' tag we try to find if it comes from a third party
	original_document.xpath('.//script').each {|script|
		#p script.to_html
		thirdp = false
		scriptSRCnode = script.attributes()['src']
		scriptSRC = ""
		if scriptSRCnode != nil
			scriptSRC = scriptSRCnode.value
		end
		#p scriptSRC
		numberofscripts = numberofscripts + 1
		if (scriptSRC!="")&&(scriptSRC =~ /:\/\/(.*?)\//)
			scriptHost = $1				#scriptHost stores the host of the script, e.g. www.cs.virginia.edu stores .virginia.edu
			scriptworldID = ((Digest::MD5.hexdigest(scriptSRC))[0,5]).hex % 1000
			p scriptworldID
			scriptHost =~ /.*[\.\/](.*?\..*?)$/
			if ($1 != nil)
				scriptHost = $1
			end
			#puts scriptSRC+"    "+scriptHost			
			unless host.include?(scriptHost)
				thirdp = true
			end
			#wipe out the exceptions
			exceptions.each{|exception|
				if (exception.include?(scriptHost)) 
					thirdp = false
				end
			}
			#puts scriptSRC
			if (thirdp == true)
				untrustedscripts.push(scriptworldID)
				script.set_attribute('worldID',scriptworldID.to_s) rescue nil
				script.set_attribute('ACL',"#{scriptworldID.to_s};") rescue nil	#script should be able to see itself
				script.set_attribute('ROACL',"#{scriptworldID.to_s};") rescue nil	#and... modify itself
			end
		elsif (script.to_html.include?("google_ad_client"))||(script.to_html.include?("ga.js"))		#for google ads who put their required params in another script, also google analytics.
			script.set_attribute('worldID',"1") rescue nil
			script.set_attribute('ACL',"1") rescue nil	#script should be able to see itself
			script.set_attribute('ROACL',"1") rescue nil	#and... modify itself	
		end
   	}
	totalworldID = ""
	untrustedscripts.each{|s|
		totalworldID = totalworldID+s.to_s+";"
	}
	#outputfile.syswrite("Finished 3rd-p script "+url+"\n")

	
	#puts "total number of scripts is: " + numberofscripts.to_s
	#done identifying all third party script
	#start calculating the difference between these two pages
	#puts "begin of calculating"
	$count = 0
	ele = Hash.new
	ele_t = Hash.new	
	ele_t_s = Hash.new		#stands for individual text nodes, not concatenated.
	to_add_acl = Hash.new
	to_remove_acl = Hash.new	#one node can have many text nodes as its children. we need to confirm all of them are identical before marking it public.
	#push all tag attrs into the hash
	#p dummy_document
	dummy_document.traverse do |dum_e|
		if (dum_e.elem?())&&(!dum_e.text?())
			ele[Digest::MD5.hexdigest(dum_e.values.to_s)] = 1
			ele_t[Digest::MD5.hexdigest(dum_e.inner_html)] = 1
		end
		if (dum_e.text?())
			ele_t_s[Digest::MD5.hexdigest(dum_e.content)]=1
		end
	end
	#p "Finished hashing dom "+url+"\n"

	#test specific node
=begin
	original_document.xpath(".//p[@id='pic_caption']").each {|test|
		p test.values.to_s
		p test.inner_html
		p test.elem?()
	}
=end
	#search the real request for these tags. If match, add ACLs
	original_document.traverse do |ori_e|
	#gives the node with no text in it and has same attrs ROACLs and ACLs.
		if (ori_e.elem?())&&(!ori_e.text?())
			if ((ele.key?(Digest::MD5.hexdigest(ori_e.values.to_s))))
				flag = 0
				ori_e.children.each {|child|
					if child.text?() 
						flag = 1
					end
				}
				if flag == 0
					to_add_acl[ori_e.pointer_id()] = 1
				end
			#else
				#ori_e.attributes['style'] += " background-color: #FFFF00;"
			end
		end

	#also gives the parent node ACL if textnode is same.
		if ((ori_e.text?())&&(ori_e.parent != nil)&&(ori_e.parent.elem?()))
			if ((ele.key?(Digest::MD5.hexdigest(ori_e.parent.values.to_s)))&&(ele_t_s.key?(Digest::MD5.hexdigest(ori_e.content))))
				#ori_e.parent.set_attribute('ACL','2;') rescue nil
				to_add_acl[ori_e.parent.pointer_id()]=1
				totalpubliclength = totalpubliclength + ori_e.content.length
			end
			if ((ele.key?(Digest::MD5.hexdigest(ori_e.parent.values.to_s)))&&(!ele_t_s.key?(Digest::MD5.hexdigest(ori_e.content))))
				#ori_e.parent.set_attribute('ACL','2;') rescue nil
				to_remove_acl[ori_e.parent.pointer_id()]=1
			end		
			totallength = totallength + ori_e.content.length
		end
	end
	original_document.traverse do |ori_e|
		if (to_add_acl.key?(ori_e.pointer_id()))
			totalpublicnodecount += 1
			ori_e.set_attribute('ACL',totalworldID)
			ori_e.set_attribute('ROACL',totalworldID)
		end
		if (ori_e.elem?())
			totalnodecount += 1
		end
	end
	original_document.traverse do |ori_e|
		if (to_remove_acl.key?(ori_e.pointer_id()))
			if ori_e.has_attribute?('ACL')
				totalpublicnodecount -= 1
				ori_e.remove_attribute('ACL')
				ori_e.remove_attribute('ROACL')
			end
		end
	end
	#puts "#{original_document}"
	outputFile = File.new(whitelist+"_stat",'a')
	outputFile.syswrite("public characters: "+totalpubliclength.to_s+"\n")
	outputFile.syswrite("total characters: "+totallength.to_s+"\n")
	outputFile.syswrite("public node count: "+totalpublicnodecount.to_s+"\n")
	outputFile.syswrite("total node count: "+totalnodecount.to_s+"\n")
	if totallength!=0
		outputFile.syswrite("Char percentage: "+(totalpubliclength.to_f/totallength).to_s+"\n")	
	end
	if totalnodecount!=0
		outputFile.syswrite("Node percentage: "+(totalpublicnodecount.to_f/totalnodecount).to_s+"\n")	
	end
	outputFile.syswrite("---------------------------------------------\n")
	outputFile.close()
	#outputfile.syswrite("finish parsing "+url+"\n")
	p "function invocation done"
	return "#{original_document.to_html}"

end

def extractPolicy(file)
	#TODO: For performance reasons, we cache the policy
end
#main function begins
url = ""
host = ""
hostChopped = ""
policyFile = ""
whitelist = ""
p "A new request"
#p $requestheader
if ($httpresponse =~ /^[^{]/)				#response should not start w/ '{', otherwise it's a json response
	#getting the URL and host of the request
	if $requestheader =~ /GET\s(.*?)\sHTTP/		#get the URL of the request; We ignore POST since it might cause problems.
		url = $1
		digestzyc = Digest::MD5.hexdigest(url)
		if $requestheader =~ /Host:\s(.*)/	#get the host of the request
			host = $1
			host =~ /.*[\.\/](.+?\..+?)$/
			host2 = $1
			if host2 == nil 
				host2 = host
			end
			hostChopped = host2.chop		# The $1 matches the string with a CR added. we don't want that.
			hostChopped = hostChopped.gsub(/(\.|\/|:)/,'')
			policyFile = "Policy/#{hostChopped}/#{digestzyc}"
			whitelist = "Policy/#{hostChopped}/#{hostChopped}_whitelist"
		end
	end
	#check if the policy file already exists
	if not(File.exists?("#{policyFile}"))
		#create the directory if needed
		if !(File.directory? "Policy/")
			Dir::mkdir("Policy/")
		end			
		if !(File.directory? "Policy/#{hostChopped}/")
			Dir::mkdir("Policy/#{hostChopped}/")
		end
		$httpresponse = process($httpresponse,url,host,whitelist)
		#parse the file
	elsif
		#extract policy from existing file
		extractPolicy(policyFile)
	end

p "request ended"
end


