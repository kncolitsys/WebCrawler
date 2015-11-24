<!---
	WebCrawler - recursively a list of urls
	
	To use the web crawler, first create a component that implements IWebVisitor's match() and process() methods.
	Create a web crawler instance and set it's visitor property to an instance of your IWebVisitor component.
	Call crawl(urls).  WebCrawler will iterate through the urls, calling the match(fileName) method of you IWebVisitor.
	If match() returns true, WebCrawler will call the cacheInfo(url) method to ask for attributes of any cached
	version your visitor may have.  If no information is provided or the cache is out of date, the crawler calls
	process(url, header, content) method, adding any urls returned by the function to the list of urls to visit.
	
	Note:	These two methods are separated so that the crawler only needs to fetches the url contents if a visitor
			matches the url pattern.
			
	(c) 2008 RocketBoots Pty Ltd
	
	The WebCrawler library is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    The WebCrawler library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
	
	$Id: WebCrawler.cfc 367 2009-03-06 03:42:15Z robinhilliard $
 --->
<cfcomponent output="false" defaultArrayProperty="urls">
	
	<cfscript>
		// Timing for thread sleeps
		SHORT_DELAY = 50;	
		LONG_DELAY = 10000;
		
		// Lock names
		URL_CHECK_QUEUE_LOCK = "urlQueueLock";
		URL_PROCESSING_QUEUE_LOCK = "urlProcessingQueueLock";
	
		// An IWebVisitor
		_visitor = "";
		
		// Path to crawl if not passed to crawl
		this.urls = arrayNew(1);
		
		// Set how many threads are used for URL retrieval 
		this.maxThreads = 5;
		
		// Add links from previously cached pages to the check queue, useful after interrupted crawl
		this.recheckCachedLinks = false;
		
		// URLs to be checked by the visitor
		urlCheckQueue = arrayNew(1);
		
		// URLs to be processed by the visitor
		urlProcessingQueue = arrayNew(1);
		
		// Distinct URLs already checked, used to prevent infinite recursion
		checkedUrls = structNew();
	</cfscript> 
	
	
	
	<!---
		@param visitor	An implementor of com.rocketboots.util.IWebVisitor.
	 --->
	<cffunction access="public" name="setVisitor" returntype="void" output="false">
		<cfargument name="visitor" type="com.rocketboots.util.web.IWebVisitor" required="true">
		<cfset _visitor = visitor>
	</cffunction>
	
	<cffunction access="public" name="getVisitor" returntype="com.rocketboots.util.web.IWebVisitor">
		<cfreturn _visitor>
	</cffunction>
	
	
	
	<!---
		Crawl until all possible urls are exhausted
		
		@param urls	Array of URLs to check
	 --->
	<cffunction access="public" name="crawl" returntype="void" output="false">
		<cfargument name="urls" type="array" required="false" default="#this.urls#">
		
		<cfset var nextURLIndex = 0>
		
		<cflog text="WebCrawler.crawl(): STARTING with #arrayLen(urls)# URLs">

		<!--- Copy URLs into the check queue for checking --->
		<cfset urlCheckQueue = urls>
		
		<!--- Bounce the processing threads --->
		<cfset stopThreads()>
		<cfset startThreads()>
		
		<!--- Keep checking URLs until the URL checking and processing queues remain empty after a LONG_DELAY wait --->
		<cfloop condition="true">
			
			<!--- Get the next URL to check --->
			<cfset nextUrl = "">
			<cflock name="#URL_CHECK_QUEUE_LOCK#" type="exclusive" throwontimeout="true" timeout="10">
				<cfif arrayLen(urlCheckQueue) gt 0>
					<cfset nextURLIndex = ceiling(rand() * arrayLen(urlCheckQueue))>
					<cfset nextUrl = urlCheckQueue[nextURLIndex]>
					<cfset arrayDeleteAt(urlCheckQueue, nextURLIndex)>
				</cfif>
			</cflock>
			
			<!--- 
				If there is one we haven't already seen, and the visitor is interested in looking at it, 
				add it to the processing queue
			 --->
			<cfif nextUrl neq "">
				<!--- <cflog text="WebCrawler.crawl(): checking URL #nextURL#"> --->
				<!--- <cflog text="WebCrawler.crawl(): checking #nextURL#"> --->
				<cfif getVisitor().match(nextUrl)>
					<cflock name="#URL_PROCESSING_QUEUE_LOCK#" type="exclusive" throwontimeout="true" timeout="10">
						<cfset arrayAppend(urlProcessingQueue, nextUrl)>
					</cflock>
					<!--- <cflog text="WebCrawler.crawl(): Added URL #nextURL# to processing queue"> --->
				</cfif>
				
			<!--- Otherwise, wait a while to see if more urls are added to the check queue by the processing threads --->	
			<cfelse>
				<cfthread action="sleep" duration="#LONG_DELAY#"/>
				<cflock name="#URL_CHECK_QUEUE_LOCK#" type="readonly" throwontimeout="true" timeout="10">
					<cflock name="#URL_PROCESSING_QUEUE_LOCK#" type="readonly" throwontimeout="true" timeout="10">
						<cflog text="WebCrawler.crawl(): urlCheckQueue = #arrayLen(urlCheckQueue)# urlProcessingQueue = #arrayLen(urlProcessingQueue)#">
						<cfif arrayLen(urlCheckQueue) eq 0 and arrayLen(urlProcessingQueue) eq 0>
							<!--- All queues empty, bail out --->
							<cflog text="WebCrawler.crawl(): FINISHED">
							<cfbreak>
						</cfif>
					</cflock>
				</cflock>
			</cfif>
			
		</cfloop>
		
		<!--- Kill the processing threads before we stop --->
		<cfset stopThreads()>
		
	</cffunction>
	
	
	
	<!---
		Stop processing threads
	 --->
	<cffunction access="private" name="stopThreads" returntype="void" output="false">
		<cfloop from="1" to="#this.maxThreads#" index="threadId">
			<cftry>
				<cfthread action="terminate" name="urlProcessor#threadId#"/>
				<cflog text="WebCrawler.stopThreads(): Stopped urlProcessor#threadId#">
			<cfcatch type="any"></cfcatch>
			</cftry>
		</cfloop>
	</cffunction>
	
	
	
	<!---
		Start processing threads
	 --->
	<cffunction access="private" name="startThreads" returntype="void" output="false">
		
		<!---
			Create multiple threads to read from the shared processing queue - we benefit from multi-threading here
			because threads are going to sleep all the time waiting for cfhttp results to come back over the network,
			and other threads can take their place on the CPU while they do that.
		--->
		<cfloop from="1" to="#this.maxThreads#" index="threadId">
		
			<cfthread action="run" name="urlProcessor#threadId#" threadName="urlProcessor#threadId#">
			
				<cftry>
					<!--- Threads go forever until killed --->
					<cfloop condition="true">
					
						<!--- Get the next URL for processing off the common queue --->
						<cfset nextUrl = "">
						<!--- <cflog text="WebCrawler: #threadName# checking processing queue"> --->
						<cflock name="#URL_PROCESSING_QUEUE_LOCK#" type="exclusive" throwontimeout="true" timeout="10">
							<cfif arrayLen(urlProcessingQueue) gt 0>
								<!--- Random index, to distribute load across all sites being crawled --->
								<cfset nextURLIndex = ceiling(rand() * arrayLen(urlProcessingQueue))>
								<cfset nextUrl = urlProcessingQueue[nextURLIndex]>
								<cfset arrayDeleteAt(urlProcessingQueue, nextURLIndex)>
							</cfif>
						</cflock>
						
						<!--- Got one --->
						<cfif nextUrl neq "">
							<!--- <cflog text="WebCrawler: #threadName# processing #nextUrl#"> --->
							<!--- Add visitor cache information to the request, so that we get a 304 if the content is unchanged --->
							<cfset cacheInfo = getVisitor().cacheInfo(nextUrl)>
							<cfhttp url="#nextUrl#" resolveurl="true">
								<cfif structKeyExists(cacheInfo, "eTag")>
									<cfhttpparam type="header" name="If-None-Match" value="#cacheInfo.eTag#">
								</cfif>
								<cfif structKeyExists(cacheInfo, "lastModified")>
									<cfhttpparam type="header" name="If-Modified-Since" value="#cacheInfo.lastModified#">
								</cfif>
							</cfhttp>
							
							<!--- 
								Pass response to the visitor for processing and add any URLs it returns
								back into the shared check queue
							 --->
							<cftry>
								<cfif cfhttp.statusCode eq "200 OK" and cfhttp.text>
									<cfset newUrls = getVisitor().process(nextUrl, cfhttp.responseHeader, cfhttp.fileContent)>
									
								<cfelseif this.recheckCachedLinks and structKeyExists(cacheInfo, "htmlContent")>
								
									<cfset stFakeHeader = structNew()>
									<cfset stFakeHeader.eTag = cacheInfo.eTag>
									<cfset stFakeHeader.lastModified = cacheInfo.lastModified>
									<cfset newUrls = getVisitor().process(nextUrl, stFakeHeader, cacheInfo.htmlContent)>
								
								<cfelse>
									<cfset newUrls = arrayNew(1)>
									
								</cfif>
							<cfcatch>
								<cflog text="WebCrawler: #threadName# visitor threw exception #cfcatch.message# #cfcatch.detail# while processing #nextUrl# - continuing">
								<cfset newUrls = arrayNew(1)>
								
							</cfcatch>
							</cftry>
							
							<cfif arrayLen(newUrls) gt 0>
								<cflock name="#URL_CHECK_QUEUE_LOCK#" type="exclusive" throwontimeout="true" timeout="10">
									<cfloop from="1" to="#arrayLen(newUrls)#" index="i">
										<cfif not structKeyExists(checkedUrls, newUrls[i])>
											<cfset arrayAppend(urlCheckQueue, newUrls[i])>
											<cfset checkedUrls[newUrls[i]] = true>
										</cfif>
									</cfloop>
								</cflock>
							</cfif>
							
						<cfelse>
							<!--- The processing queue is empty, take a nap --->
							<cfthread action="sleep" duration="#SHORT_DELAY#"/>
						</cfif>
						
					</cfloop>
				<cfcatch type="any">
					<cflog text="WebCrawler: #threadName# threw exception #cfcatch.message# #cfcatch.detail# - terminating">
					<cfabort>
				</cfcatch>
				</cftry>
				
			</cfthread>
			<cflog text="WebCrawler.startThreads(): started urlProcessor#threadId#">
		</cfloop>
		
	</cffunction>

</cfcomponent>