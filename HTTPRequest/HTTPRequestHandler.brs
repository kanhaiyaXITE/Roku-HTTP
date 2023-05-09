sub HTTPResponseHandler(msg, requestUri)
	' msg from MessagePort
	response = msg.GetString()
	responseCode = msg.GetResponseCode()
	topParams = m.top.params
	logString = topParams.requestFor + " " + topParams.requestMethod

	json = {}
	if response.instr("{") = 0 or response.instr("[") = 0:
		if topParams.fileUri <> invalid and topParams.fileUri <> "" and not m.top.getScene().deviceInfo.old
			? topParams.fileUri
			fileWritten = WriteAsciiFile(topParams.fileUri, response)
			? topParams.requestFor + " file written: ";
			? fileWritten
		end if
		json = ParseJson(response)
		if type(json) = "roArray" then json = {contentData: json}
	else:
		? "Error Log: "
		? response
		? type(response)
		? msg.GetResponseHeaders()
	end if

	if topParams.forceResponseCode <> invalid then responseCode = topParams.forceResponseCode

	if responseCode = 200
	 	if msg.GetResponseHeaders()["content-type"] = "text/xml"  or msg.GetResponseHeaders()["content-type"] = "text/xml; charset=utf-8"
	       json = XMLParser(response, topParams.requestFor, topParams.misc)
	    else
	       json = ACParser(json, topParams.requestFor)
	    end if
		if json = invalid then json = {}
		if topParams.requestFor.instr("autoPlayDetails") >= 0 or topParams.requestFor.instr("contentDetails") >= 0 or topParams.requestFor.instr("videoDetails") >= 0 or topParams.requestFor.instr("trailerDetails") >= 0 or topParams.requestFor.instr("videoPageDetails") >= 0:
			responseHeader = msg.GetResponseHeaders()
			cookies = m.request.GetCookies("viewlift.com", "/")

			json.append({
				cookies: cookies
			})
		end if
		setJson(json)
	else if responseCode = -28:
	'' or responseCode = 504:
		' Failure Reason: Connection timed out after 30001 milliseconds
		' No response body
		Print "Startup: Response handler - Request timed out"
		if topParams<>invalid and topParams.requestRetry<>invalid and topParams.requestRetry:
			errorObj = {
				error: true,
				requestFor: topParams.requestFor,
				requestName: topParams.requestName,
				code: responseCode,
				msg: "Request Timed Out"
			}
			if m.userRetry <> invalid then errorObj.userRetry = m.userRetry
			m.top.errorObj = errorObj
		else:
			m.requestRetry = true
			externalRequest()
		end if
	else:
		failureReason = msg.GetFailureReason()
		Print Substitute("Startup: Response handler - failure reason: {0}. Code: {1}", failureReason, responseCode.ToStr())
		Print "Startup: Response handler - failure response: " response
		Print "Startup: Response handler - failure params: " topParams
		if (responseCode = 401) AND not requestUri.instr("identity/refresh") >= 0
			Print "Startup: Tokens unauthorized"
			newToken()
		else if response.instr("expired") >= 0
			Print "Startup: Tokens expired"
			newToken()
		else
			if json = invalid then json = {}
			json.responseCode = responseCode
			if response.instr("{") = 0 then response = ParseJson(response)
			json.response = response
			if json.error = invalid then json.error = true
			setJson(json)
		end if
 	end if
end sub