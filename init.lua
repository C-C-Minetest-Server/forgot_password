local MP = minetest.get_modpath("forgot_password")
local S = minetest.get_translator("forgot_password")
local storage = minetest.get_mod_storage()
local settings = minetest.settings

local http = minetest.request_http_api and minetest.request_http_api() or error("Please allow forgot_password to access the Minetest HTTP API!")

local url = settings:get("forgot_password.http_url") or error("Please set forgot_password.http_url!")
local token = settings:get("forgot_password.http_token") or error("Please set forgot_password.http_token!")

local confirm = {
	template_path = settings:get("forgot_password.confirm_email_template") or MP .. "/email/confirm.txt",
	template = "", -- Load it later
	subject = settings:get("forgot_password.confirm_email_subject") or "Confirm your Minetest account email address"
}

local passwd = {
	template_path = settings:get("forgot_password.passwd_email_template") or MP .. "/email/passwd.txt",
	template = "", -- Load it later
	subject = settings:get("forgot_password.passwd_email_subject") or "Recover your Minetest account"
}

do -- Load confirm template
	local f = io.open(confirm.template_path)
	if f then
		confirm.template = f:read("*a")
	else
		error("forgot_password.confirm_email_template contains an invalid value.")
	end
end

do -- Load password recover template
	local f = io.open(passwd.template_path)
	if f then
		passwd.template = f:read("*a")
	else
		error("forgot_password.passwd_email_template contains an invalid value.")
	end
end

local charset = {}  do -- [0-9a-zA-Z]
    for c = 48, 57  do table.insert(charset, string.char(c)) end
    for c = 65, 90  do table.insert(charset, string.char(c)) end
    for c = 97, 122 do table.insert(charset, string.char(c)) end
end

local function randomString(length)
	if not length then length = 15 end
    if length <= 0 then return '' end
    return randomString(length - 1) .. charset[math.random(1, #charset)]
end

function substparam(str,key,value)
	return string.gsub(str,"{" .. key .. "}",value)
end

function confirm.get_email(name,email,confirm_code)
	local RSTR = confirm.template
	RSTR = substparam(RSTR,"name",name)
	RSTR = substparam(RSTR,"email",email)
	RSTR = substparam(RSTR,"confirm_code",confirm_code)
	return RSTR
end

function passwd.get_email(name,ip,reset_login_name)
	local RSTR = passwd.template
	RSTR = substparam(RSTR,"name",name)
	RSTR = substparam(RSTR,"ip",ip)
	RSTR = substparam(RSTR,"reset_login_name",reset_login_name)
	return RSTR
end

function sendmail(to,subject,body)
	return http.fetch_async({
		url = url,
		method = "POST",
		data = {
			token = token,
			to = to,
			subject = subject,
			body = body,
		},
		user_agent = "Minetest-Forget-Password",
		multipart = true
	})
end

-- Set Email
minetest.register_chatcommand("set_email",{
	description = S("Set email address for password recovery"),
	param = S("<email address>"),
	func = function(name,param)
		if not param:match("^[%w.]+@%w+%.%w+$") then
			return false, "Invalid email address!"
		end
		local confirm_token = randomString()
		storage:set_string("confirm-" .. name,confirm_token)
		storage:set_string("tmp-email-" .. name,param)
		local body = confirm.get_email(name,param,confirm_token)
		sendmail(param,confirm.subject,body)
		return true, "Confirm email sent."
	end,
})
minetest.register_chatcommand("confirm_email",{
	description = S("Confirm email"),
	param = S("<confirm code>"),
	func = function(name,param)
		local confirm_token = storage:get("confirm-" .. name)
		if param == confirm_token then
			local tmp_email = storage:get("tmp-email-" .. name)
			if not tmp_email then
				return false, "Please run /set_email first!"
			end
			storage:set_string("email-" .. name,tmp_email)
			return true, "Email set."
		end
		return false, "Code does not match."
	end,
})

-- Password recover
minetest.register_on_prejoinplayer(function(name,ip)
	minetest.log("Processing player" .. name)
	local t = {}
	for str in string.gmatch(name, "([^*-]+)") do
		table.insert(t,str)
	end
	if t[2] == "FP" then
		-- Forget password!
		local email = storage:get("email-" .. t[1])
		if email then
			local reset_login_token = randomString()
			storage:set_string("recover-" .. reset_login_token,t[1])
			local reset_login_name = reset_login_token
			local body = passwd.get_email(t[1],ip,reset_login_name)
			sendmail(email,passwd.subject,body)
		end
		return "Password reset email sent."
	end
	local sname = storage:get("recover-" .. name)
	if sname and sname ~= "" then
		storage:set_string("recover-" .. name,"")
		minetest.get_auth_handler().set_password(sname,minetest.get_password_hash(sname, name))
		return "Password of " .. sname .. " set to " .. name .. ". \nPLEASE CHANGE YOUR PASSWORD AFTER LOGIN!"
	end
end)
