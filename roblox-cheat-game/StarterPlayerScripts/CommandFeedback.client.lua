-- CommandFeedback (LocalScript in StarterPlayer > StarterPlayerScripts)
-- Shows replies from chat commands and the server list as system
-- messages in chat (green for success, red for errors).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local remotes = ReplicatedStorage:WaitForChild("CheatRemotes")
local feedback = remotes:WaitForChild("CommandFeedback")

local function escapeRichText(text)
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

feedback.OnClientEvent:Connect(function(text, isError)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local channel = channels and channels:FindFirstChild("RBXGeneral")
	if not channel then
		print(text)
		return
	end
	local color = isError and "#ff5c5c" or "#7cd67c"
	channel:DisplaySystemMessage(
		string.format('<font color="%s">%s</font>', color, escapeRichText(tostring(text)))
	)
end)
