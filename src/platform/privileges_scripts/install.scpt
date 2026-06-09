on run {daemon_file, agent_file, user}

  set sh1 to "echo " & quoted form of daemon_file & " > /Library/LaunchDaemons/com.luoda.LUODA_service.plist && chown root:wheel /Library/LaunchDaemons/com.luoda.LUODA_service.plist;"

  set sh2 to "echo " & quoted form of agent_file & " > /Library/LaunchAgents/com.luoda.LUODA_server.plist && chown root:wheel /Library/LaunchAgents/com.luoda.LUODA_server.plist;"

  set sh3 to "cp -rf /Users/" & user & "/Library/Preferences/com.luoda.LUODA/LUODA.toml /var/root/Library/Preferences/com.luoda.LUODA/;"

  set sh4 to "cp -rf /Users/" & user & "/Library/Preferences/com.luoda.LUODA/LUODA2.toml /var/root/Library/Preferences/com.luoda.LUODA/;"

  set sh5 to "launchctl load -w /Library/LaunchDaemons/com.luoda.LUODA_service.plist;"

  set sh to sh1 & sh2 & sh3 & sh4 & sh5

  do shell script sh with prompt "LUODA wants to install daemon and agent" with administrator privileges
end run
