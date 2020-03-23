
DiscoursePrivateReplies::Engine.routes.draw do
  put "/enable" => "private_replies#enable"
  put "/disable" => "private_replies#disable"
end

