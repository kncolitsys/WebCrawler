<!---
	IWebVisitor - Implement this interface to create a visitor that works with WebCrawler.  
	Note that implementations _must_ be thread-safe.
	
	@see com.rocketboots.util.WebCrawler
			
	(c) 2008 RocketBoots Pty Ltd
	
	The WebCrawler library is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    The WebCrawler library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
	
	$Id: IWebVisitor.cfc 315 2009-02-22 22:46:38Z robinhilliard $
 --->
<cfinterface>

	<!---
		Tell the crawler if we are interested in looking at a url
		
		@param		url		fully qualified URL
		@returns 	true 	if you would like to process this URL
	 --->
	<cffunction access="public" name="match" returntype="boolean">
		<cfargument name="url" type="string">
	</cffunction>
	
	
	
	<!---
		Give the crawler information about our cached version of the URL, if any
		
		@parm		url		fully qualified URL
		@returns	structure with two optional keys: eTag and lastModified. If one or both
					are specified they are used to qualify our query the web server to only 
					return content if it has been updated.
	 --->
	<cffunction access="public" name="cacheInfo" returntype="struct">
		<cfargument name="url" type="string">
	</cffunction>
	
	
	<!---
		Process the contents of a URL where match(url) = true and our cache (if any) was
		out of date
		
		@param		url		fully qualified URL
		@param		headers http headers
		@param		content	URL content
		@returns	array of additional urls to process
	 --->
	<cffunction access="public" name="process" returntype="array">
		<cfargument name="url" type="string">
		<cfargument name="headers" type="struct">
		<cfargument name="content" type="string">
	</cffunction>
	


</cfinterface>
