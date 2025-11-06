#!/bin/bash


# if password parameter provided
if [ $# -eq 0 ]; then
    echo "ERROR: please run this script with new root password"
    echo "Usage: $0 new-root-password"
    exit 1
fi

PASSWORD="$1"

# password validation
validate_password() {
    local password="$1"

    if [ ${#password} -lt 8 ]; then
        echo "ERROR: the password length must >= 8 characters!!!"
        return 1
    fi

    return 0
}

if ! validate_password "$PASSWORD"; then
    exit 1
fi

echo "resetting GitLab root password ..."


docker exec gitlab gitlab-rails runner -e production "
begin
  user = User.find_by(username: 'root')
  if user.nil?
    puts 'ERROR: failed to find user root'
    exit 1
  end
  
  user.password = '${PASSWORD}'
  user.password_confirmation = '${PASSWORD}'
  
  if user.save
    puts '✓ Succeed to set the password of Root'
  else
    puts '✗ Failed to set the password of Root'
    user.errors.full_messages.each do |message|
      puts '  - ' + message
    end
    exit 1
  end
rescue => e
  puts 'ERROR: ' + e.message
  exit 1
end
"
