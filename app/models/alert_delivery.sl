# One alert sent on one channel. The key is "<channel>_<event>_<subject>", so a
# transition is announced once per channel however often the code is reached.
# Fields: channel_id, event, subject_id, at, summary.
class AlertDelivery < Model
end
