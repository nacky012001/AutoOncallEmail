require 'mail'
require 'fileutils'

def send_oncall_email(sender, sender_email, oncall_date, tel)
  Mail.deliver do
    delivery_method :smtp, address: "moexc01.mo.laxino.com", :openssl_verify_mode => 'none'
    from    sender_email
    to      ['LMRnD.DevOps@laxino.com', 'LMRnD.GameDevelopment@laxino.com', 'LMRnD.InfrastructureEngineering@laxino.com']
    cc      'helpdesk@laxino.com'
    subject "#{sender} is oncall today (#{oncall_date.day}/#{oncall_date.month})(Tel: #{tel})"
    body ("As title.\n\nRegrads,\n#{sender}.")
  end
end

def send_warning_email(sender, sender_email)
  Mail.deliver do
    delivery_method :smtp, address: "moexc01.mo.laxino.com", :openssl_verify_mode => 'none'
    from    'non-reply@AUTOONCALLEMAIL'
    to      sender_email
    subject "Warning: You have not set your next oncall date for more than 15 days"
    body ("As title.\n\nRegrads,\nAuto Oncall Email Alert.")
  end
end


def send_alert_email(sender, sender_email)
  Mail.deliver do
    delivery_method :smtp, address: "moexc01.mo.laxino.com", :openssl_verify_mode => 'none'
    from    'non-reply@AUTOONCALLEMAIL'
    to      sender_email
    subject "Alert: Failed to send on call emails"
    body ("As title.\n\nRegrads,\nAuto Oncall Email Alert.")
  end
end

def acquire_pid_file(file_full_name)
  begin
    Timeout.timeout(3) {
      if !File.file? file_full_name
        dir = File.dirname(file_full_name)
        FileUtils.mkdir_p(dir)
      end
      @@pid_file = File.open(file_full_name, File::RDWR|File::CREAT)
      @@pid_file.flock File::LOCK_EX
      @@pid_file.write(Process.pid.to_s)
      @@pid_file.flush
    }
    return true
  rescue Exception => ex
    puts ex
    puts "Warning: failed to acquire pid file, maybe another instance is still running."
    return false
  end
end

def release_pid_file
  @@pid_file.flock File::LOCK_UN if @@pid_file
end

def today?(now, date)
  ((now - date).to_i / (3600 * 24)) == 0
end

def not_yet_send_email?(date, last_email_time)
  date.nil? || last_email_time.nil? || date > last_email_time
end

def process
  if acquire_pid_file(File.join(File.dirname(__FILE__), 'send_oncall_email.pid'))
    now = Time.now
    shift_start_time = Time.new(now.year, now.month, now.day, 10, 00)
    shift_end_time = Time.new(now.year, now.month, now.day, 10, 30)

    engines = YAML.load_file(File.join(File.dirname(__FILE__), 'send_oncall_email.yml'))[:oncall_engines]
    dat_path = File.join(File.dirname(__FILE__), './send_oncall_email.dat')
    dat = File.file?(dat_path) ? YAML.load_file(dat_path) : {}
    
    engines.each do |engine|
      dates = engine[:dates].map { |d| yy, mm, dd = d.split('-'); Time.new(yy, mm, dd) }
      date = dates.select { |d| today?(now, d) }.first
      last_email_time = dat[engine[:name]]

      return unless not_yet_send_email?(date, last_email_time)

      if date
        if shift_start_time <= now && now <= shift_end_time
          send_oncall_email(engine[:name], engine[:email], date, engine[:tel]) 
          dat[engine[:name]] = date
        elsif now > shift_end_time
          puts "ALERT!! Failed to send oncall email for #{engine[:name]}."
          send_alert_email(engine[:name], engine[:email]) 
        end
      end

      latest_oncall_date = dates.sort.last
      if (now - latest_oncall_date).to_i / (3600 * 24) >= 15
        send_warning_email(engine[:name], engine[:email])
        puts "Warning: #{engine[:name]} has not set next oncall date."
      end
    end
    
    dat_file = File.open(dat_path, File::WRONLY|File::TRUNC|File::CREAT)
    dat_file.write(dat.to_yaml)
    dat_file.close

    release_pid_file
  end
end

process
