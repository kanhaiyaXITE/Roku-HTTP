sub init()
	m.top.functionName = "requestTask"
end sub

sub requestTask()
	topParams = m.top.params
	if m.top.getScene().deviceInfo.old
		externalRequest()
	else
		if topParams.fileUri <> invalid then
			if  topParams.fileUri <> "" then
				tmpFileReader = ReadAsciiFile(topParams.fileUri)
			else
				tmpFileReader=""
			end if
			if tmpFileReader <> "" then
				cacheRequest(tmpFileReader)
			else:
				externalRequest()
			end if
		else if topParams.uri<>invalid and topParams.uri.instr("pkg") >= 0 then
			internalRequest()
		else:
			externalRequest()
		end if
	end if
end sub

sub cacheRequest(file)
	topParams = m.top.params
	? "Reading cached: "; topParams.fileUri
	txtJson = ParseJson(file)
	json = ACParser(txtJson, topParams.requestFor)
	setJson(json)
end sub

sub internalRequest()
	topParams = m.top.params
	? "Reading local: "; topParams.uri
	file = ReadAsciiFile(topParams.uri)
	if file <> "":
		txtJson = ParseJson(file)
		json = ACParser(txtJson, topParams.requestFor)
		setJson(json)
	end if
end sub

sub externalRequest()
	topParams = m.top.params
	logString = topParams.requestFor + " " + topParams.requestMethod
	if topParams.uri<>invalid
		requestUri = topParams.uri.EncodeUri()
		if requestUri.inStr("++&++")>=0
			requestUri=requestUri.Replace("++&++","%26")
		else if requestUri.inStr("+&+")>=0
			requestUri=requestUri.Replace("+&+","+%26+")
		end if

		' ? logString; " REQUEST URL: "; requestUri

		port = CreateObject("roMessagePort")
		request = CreateObject("roUrlTransfer")
		request.RetainBodyOnError(true)
		request.SetMessagePort(port)
		request.SetRequest(topParams.requestMethod)
		request.SetUrl(requestUri)

		if requestUri.instr("gzip=") >= 0 then request.EnableEncodings(true)

		if (requestUri.instr("api.viewlift.com") >= 0 or requestUri.instr("cached.viewlift.com") >= 0) and requestUri.instr("anonymous-token") = -1 and topParams.forceToken = "" and m.global.tokens <> invalid
			request.AddHeader("Authorization", m.global.tokens.authorizationToken)
		else if topParams.forceToken <> "" AND topParams.forceToken <> invalid
			request.AddHeader("Authorization", topParams.forceToken)
		end if

		sceneObj = m.top.getScene()
		AppCms = sceneObj.AppCMS
		if requestUri.instr("api.viewlift.com") >= 0 or requestUri.instr("cached.viewlift.com") >= 0 or requestUri.instr("prod-api-cached-2.viewlift.com") >= 0 or requestUri.instr("staging-api-cached-2.viewlift.com") >= 0
			if AppCms <> invalid and AppCms.main <> invalid and AppCms.main.__xAPIKey <> "":
				xAPIKey = AppCms.main.__xAPIKey
			else if topParams.forceApikey<>invalid and topParams.forceApikey <> "":
				xAPIKey = topParams.forceApikey
			else:
				xAPIKey = sceneObj.local.xAPIKey
			end if
			'? "xAPIKEY: "; xAPIKey
			request.AddHeader("x-api-key", xAPIKey)
		end if

		if requestUri.instr("https") >= 0:
			request.SetCertificatesFile("common:/certs/ca-bundle.crt")
			request.InitClientCertificates()
		end if

		if topParams.requestFor.instr("autoPlayDetails") >= 0 or topParams.requestFor.instr("trailerDetails") >= 0 or topParams.requestFor.instr("videoPageDetails") >= 0 or topParams.requestFor.instr("videoDetails") >= 0 or topParams.requestFor.instr("contentDetails") >= 0:
			request.EnableCookies()
		end if
		m.request = request

		if topParams.requestMethod = "POST":
			if topParams.requestFor = "deviceLinkCodeGet" then request.AddHeader("User-Agent", "AppCMS/4.9 tvOS/13.4")

			request.AddHeader("Content-Type", "application/json")
			requestBodyJson = FormatJson(topParams.requestBody)
			'?"post string=====" requestBodyJson
			if requestbodyjson=invalid then requestbodyjson=""
			requestState = request.AsyncPostFromString(requestBodyJson)
		else:
			requestState = request.AsyncGetToString()
		end if

		while requestState:
			msg = wait(0, port)
			if type(msg) = "roUrlEvent" then HTTPResponseHandler(msg, requestUri)
			exit while
		end while
	end if
end sub

sub newToken()
	'Print "Startup: Requesting new tokens"
	topParams = m.top.params
	sceneObj = m.top.getScene()
	AppCMS = sceneObj.AppCMS
	tokens = GlobalDataUtils_get("tokens")
	apiBaseUrl = m.top.getScene().APPCMS.main.apiBaseUrl
	if tokens.refreshToken <> invalid:
		'Print "Startup: New Tokens - refresh token valid"
		requestUri = apiBaseUrl + "/identity/refresh/" + tokens.refreshToken
	else:
		'Print "Startup: New Tokens - refresh token invalid"
		requestUri = apiBaseUrl + "/identity/anonymous-token?site=" + tokens.internalName
	end if

	request = CreateObject("roUrlTransfer")
	request.SetUrl(requestUri)
	request.SetRequest("GET")

	if requestUri.instr("https") >= 0:
		request.SetCertificatesFile("common:/certs/ca-bundle.crt")
		request.InitClientCertificates()
	end if

	if (requestUri.instr("api.viewlift.com") >= 0 or requestUri.instr("cached.viewlift.com") >= 0):
		if AppCMS <> invalid and AppCMS.main <> invalid and AppCMS.main.__xAPIKey <> "":
			xAPIKey = AppCMS.main.__xAPIKey
		else:
			xAPIKey = sceneObj.local.xAPIKey
		end if
		request.AddHeader("X-API-Key",xAPIKey)
	end if

	responseStr = request.GetToString()
	json = ParseJson(responseStr)

    if json <> invalid
		'Print "Startup: New Tokens - response valid: " json
        if AppCMS <> invalid and AppCMS.user <> invalid:
            AppCMS.user.authorizationToken = json.authorizationToken
            RegistryService_Write(tokens.internalName, "user", AppCMS.user)
            m.top.getScene().AppCMS = AppCMS
        end if

        tokens.authorizationToken = json.authorizationToken
		'Print "Startup: update global tokens 3"
        GlobalDataUtils_update("tokens", tokens)

        'Make sure the force token is emtied out.'
        m.forceToken = ""
        externalRequest()
    else
		'Print "Startup: New Tokens - response invalid"
        tokens.refreshToken = invalid
		'Print "Startup: update global tokens 4"
        GlobalDataUtils_update("tokens", tokens)
        newToken()
    end if
end sub

sub setJson(json)
	topParams = m.top.params
	json.requestFor = topParams.requestFor
	json.requestName = topParams.requestName
	json.misc = topParams.misc
	'TODO passing JSON consumes lot of processing. Change the result type to ContentNode
	m.top.json = json
end sub