require 'mail'

def send_mail(str)
    mail = Mail.new

    options = { :address              => "smtp.nifty.com",
                :port                 => 587,
                :domain               => "smtp.nifty.com",
                :user_name            => 'czk07503',
                :password             => 'YP3RRZV7na-K@X6n',
                :authentication       => :plain,
                :enable_starttls_auto => true  }        
    mail.charset = 'utf-8'
    mail.from "inuzuk.katsu@nifty.com"
    mail.to "inuzuka0601@gmail.com"    
    mail.subject "【エラー！】答申検索システム(Heroku)"
    mail.body str
    mail.delivery_method(:smtp, options)
    mail.deliver
end
