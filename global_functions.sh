function check_camera_attached {
	# check if cam is detected to determine if we're going to be RX or TX
	# only do this on one tty so that we don't run vcgencmd multiple times (which may make it hang)
	if [ "$TTY" == "/dev/tty1" ]; then
		CAM=`/usr/bin/vcgencmd get_camera | nice grep -c detected=1`
		if [ "$CAM" == "0" ]; then # if we are RX ...
			echo  "0" > /tmp/cam
		else # else we are TX ...
			touch /tmp/TX
			echo  "1" > /tmp/cam
		fi
	else
		#echo -n "Waiting until TX/RX has been determined"
		while [ ! -f /tmp/cam ]; do
			sleep 0.5
			#echo -n "."
		done
		CAM=`cat /tmp/cam`
	fi
}

function set_font_for_resolution {
	if [ "$CAM" == "0" ]; then # if we are RX ...
		# if local TTY, set font according to display resolution
		if [ "$TTY" = "/dev/tty1" ] || [ "$TTY" = "/dev/tty2" ] || [ "$TTY" = "/dev/tty3" ] || [ "$TTY" = "/dev/tty4" ] || [ "$TTY" = "/dev/tty5" ] || [ "$TTY" = "/dev/tty6" ] || [ "$TTY" = "/dev/tty7" ] || [ "$TTY" = "/dev/tty8" ] || [ "$TTY" = "/dev/tty9" ] || [ "$TTY" = "/dev/tty10" ] || [ "$TTY" = "/dev/tty11" ] || [ "$TTY" = "/dev/tty12" ]; then
		H_RES=`tvservice -s | cut -f 2 -d "," | cut -f 2 -d " " | cut -f 1 -d "x"`
		if [ "$H_RES" -ge "1680" ]; then
				setfont /usr/share/consolefonts/Lat15-TerminusBold24x12.psf.gz
		else
			if [ "$H_RES" -ge "1280" ]; then
				setfont /usr/share/consolefonts/Lat15-TerminusBold20x10.psf.gz
			else
				if [ "$H_RES" -ge "800" ]; then
					setfont /usr/share/consolefonts/Lat15-TerminusBold14.psf.gz
				fi
			fi
		fi
		fi
	fi
}

function read_config_file {
	if [ -e "/tmp/settings.sh" ]; then
		OK=`bash -n /tmp/settings.sh`
		if [ "$?" == "0" ]; then
			source /tmp/settings.sh
		else
			echo "ERROR: wifobroadcast config file contains syntax error(s)!"
			collect_errorlog
			sleep 365d
		fi
	else
		echo "ERROR: wifobroadcast config file not found!"
		collect_errorlog
		sleep 365d
	fi
}

function datarate_to_wifi_settings {
	case $DATARATE in
		1)
		UPLINK_WIFI_BITRATE=11
		TELEMETRY_WIFI_BITRATE=11
		VIDEO_WIFI_BITRATE=5.5
		;;
		2)
		UPLINK_WIFI_BITRATE=11
		TELEMETRY_WIFI_BITRATE=11
		VIDEO_WIFI_BITRATE=11
		;;
		3)
		UPLINK_WIFI_BITRATE=11
		TELEMETRY_WIFI_BITRATE=12
		VIDEO_WIFI_BITRATE=12
		;;
		4)
		UPLINK_WIFI_BITRATE=11
		TELEMETRY_WIFI_BITRATE=19.5
		VIDEO_WIFI_BITRATE=19.5
		;;
		5)
		UPLINK_WIFI_BITRATE=11
		TELEMETRY_WIFI_BITRATE=24
		VIDEO_WIFI_BITRATE=24
		;;
		6)
		UPLINK_WIFI_BITRATE=12
		TELEMETRY_WIFI_BITRATE=36
		VIDEO_WIFI_BITRATE=36
		;;
	esac
}

function set_video_player_based_fps {
	# mmormota's stutter-free hello_video.bin: "hello_video.bin.30-mm" (for 30fps) or "hello_video.bin.48-mm" (for 48 and 59.9fps)
	# befinitiv's hello_video.bin: "hello_video.bin.240-befi" (for any fps, use this for higher than 59.9fps)

	if [ "$FPS" == "59.9" ]; then
		DISPLAY_PROGRAM=/opt/vc/src/hello_pi/hello_video/hello_video.bin.48-mm
	else
		if [ "$FPS" -eq 30 ]; then
			DISPLAY_PROGRAM=/opt/vc/src/hello_pi/hello_video/hello_video.bin.30-mm
		fi
		if [ "$FPS" -lt 60 ]; then
			DISPLAY_PROGRAM=/opt/vc/src/hello_pi/hello_video/hello_video.bin.48-mm
		fi
		if [ "$FPS" -gt 60 ]; then
			DISPLAY_PROGRAM=/opt/vc/src/hello_pi/hello_video/hello_video.bin.240-befi
		fi
	fi
}

function get_telemtry_settings {
	if cat /boot/osdconfig.txt | grep -q "^#define LTM"; then
		TELEMETRY_UDP_PORT=5001
		TELEMETRY_TYPE=1
	fi
	if cat /boot/osdconfig.txt | grep -q "^#define FRSKY"; then
		TELEMETRY_UDP_PORT=5002
		TELEMETRY_TYPE=1
	fi
	if cat /boot/osdconfig.txt | grep -q "^#define SMARTPORT"; then
		TELEMETRY_UDP_PORT=5010
		TELEMETRY_TYPE=1
	fi
	if cat /boot/osdconfig.txt | grep -q "^#define MAVLINK"; then
		TELEMETRY_UDP_PORT=5004
		TELEMETRY_TYPE=0
	fi
}

function set_cts_protection {
	if [ "$CTS_PROTECTION" == "Y" ]; then
		VIDEO_FRAMETYPE=1 # use standard data frames, so that CTS is generated for Atheros
		TELEMETRY_CTS=1
	else # auto or N
		VIDEO_FRAMETYPE=2 # use RTS frames (no CTS protection)
		TELEMETRY_CTS=1 # use RTS frames, (always use CTS for telemetry (only atheros anyway))
	fi
	
	if [ "$TXMODE" != "single" ]; then # always type 1 in dual tx mode since ralink beacon injection broken
		VIDEO_FRAMETYPE=1
		TELEMETRY_CTS=1
	fi
}

function collect_debug {
    sleep 25

    DEBUGPATH=$1
    if [ "$DEBUGPATH" == "/boot" ]; then # if debugpath is boot partition, make it writeable first and move old logs
		nice mount -o remount,rw /boot
		mv /boot/debug.txt /boot/debug-old.txt > /dev/null 2>&1
    fi

    uptime >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    echo -n "Camera: " >>$DEBUGPATH/debug.txt
    nice /usr/bin/vcgencmd get_camera >>$DEBUGPATH/debug.txt
    nice dmesg | nice grep disconnect >>$DEBUGPATH/debug.txt
    nice dmesg | nice grep over-current >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice tvservice -s >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    nice tvservice -m CEA >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    nice tvservice -m DMT >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice iwconfig >>$DEBUGPATH/debug.txt > /dev/null 2>&1
    echo >>$DEBUGPATH/debug.txt
    nice ifconfig >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice iw reg get >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice iw list >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice ps ax >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice df -h >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice mount >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice fdisk -l /dev/mmcblk0 >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice lsmod >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice lsusb >>$DEBUGPATH/debug.txt
    nice lsusb -v >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    nice ls -la /dev >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    nice ls -la /dev/input >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    nice vcgencmd measure_temp >>$DEBUGPATH/debug.txt
    nice vcgencmd get_throttled >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    nice vcgencmd get_config int >>$DEBUGPATH/debug.txt

    echo >>$DEBUGPATH/debug.txt
    nice dmesg >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt

    nice cat /etc/modprobe.d/rt2800usb.conf >> $DEBUGPATH/debug.txt
    nice cat /etc/modprobe.d/ath9k_htc.conf >> $DEBUGPATH/debug.txt
    nice cat /etc/modprobe.d/ath9k_hw.conf >> $DEBUGPATH/debug.txt

    echo >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    nice cat /boot/wifibroadcast-1.txt | egrep -v "^(#|$)" >> $DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    nice cat /boot/osdconfig.txt | egrep -v "^(//|$)" >> $DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    nice cat /boot/joyconfig.txt | egrep -v "^(//|$)" >> $DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    echo >>$DEBUGPATH/debug.txt
    nice cat /boot/apconfig.txt | egrep -v "^(#|$)" >> $DEBUGPATH/debug.txt

    nice top -n 3 -b -d 2 >>$DEBUGPATH/debug.txt

    if [ "$DEBUGPATH" == "/boot" ]; then # if debugpath is boot partition, sync and remount ro
		sync
		nice mount -o remount,ro /boot
    fi
}

function collect_errorlog {
    sleep 3
    echo
	
    if nice dmesg | nice grep -q over-current; then
        echo "ERROR: Over-current detected - potential power supply problems!"
    fi

    # check for USB disconnects (due to power-supply problems)
    if nice dmesg | nice grep -q disconnect; then
        echo "ERROR: USB disconnect detected - potential power supply problems!"
    fi

    nice mount -o remount,rw /boot

    # check if over-temp or under-voltage occured
    if vcgencmd get_throttled | nice grep -q -v "0x0"; then
		TEMP=`cat /sys/class/thermal/thermal_zone0/temp`
		TEMP_C=$(($TEMP/1000))
		if [ "$TEMP_C" -lt 75 ]; then # it must be under-voltage
			echo
			echo "  ---------------------------------------------------------------------------------------------------"
			echo "  | ERROR: Under-Voltage detected on the TX Pi. Your Pi is not supplied with stable 5 Volts.        |"
			echo "  | Either your power-supply or wiring is not sufficent, check the wiring instructions in the Wiki. |"
			echo "  | Video Bitrate will be reduced to 1000kbit to reduce current consumption!                        |"
			echo "  ---------------------------------------------------------------------------------------------------"
			echo
			echo "  ---------------------------------------------------------------------------------------------------" >> /boot/UNDERVOLTAGE-ERROR!!!.txt
			echo "  | ERROR: Under-Voltage detected on the TX Pi. Your Pi is not supplied with stable 5 Volts.        |" >> /boot/UNDERVOLTAGE-ERROR!!!.txt
			echo "  | Either your power-supply or wiring is not sufficent, check the wiring instructions in the Wiki. |" >> /boot/UNDERVOLTAGE-ERROR!!!.txt
			echo "  | Video Bitrate will be reduced to 1000kbit to reduce current consumption!                        |" >> /boot/UNDERVOLTAGE-ERROR!!!.txt
			echo "  | When you have fixed wiring/power-supply, delete this file and make sure it doesn't re-appear!   |" >> /boot/UNDERVOLTAGE-ERROR!!!.txt
			echo "  ---------------------------------------------------------------------------------------------------" >> /boot/UNDERVOLTAGE-ERROR!!!.txt
		fi
    fi

    mv /boot/errorlog.txt /boot/errorlog-old.txt > /dev/null 2>&1
    mv /boot/errorlog.png /boot/errorlog-old.png > /dev/null 2>&1
    echo -n "Camera: "
    nice /usr/bin/vcgencmd get_camera
    uptime >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt
    echo -n "Camera: " >>/boot/errorlog.txt
    nice /usr/bin/vcgencmd get_camera >>/boot/errorlog.txt
    echo
    nice dmesg | nice grep disconnect
    nice dmesg | nice grep over-current
    nice dmesg | nice grep disconnect >>/boot/errorlog.txt
    nice dmesg | nice grep over-current >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt
    echo

    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb`

    for NIC in $NICS
    do
		iwconfig $NIC | grep $NIC
    done
	
    echo
    echo "Detected USB devices:"
    lsusb

    nice iwconfig >>/boot/errorlog.txt > /dev/null 2>&1
    echo >>/boot/errorlog.txt
    nice ifconfig >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt

    nice iw reg get >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt

    nice iw list >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt


    nice ps ax >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt

    nice df -h >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt

    nice mount >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt

    nice fdisk -l /dev/mmcblk0 >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt

    nice lsmod >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt

    nice lsusb >>/boot/errorlog.txt
    nice lsusb -v >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt
    nice ls -la /dev >>/boot/errorlog.txt
    nice ls -la /dev/input >>/boot/errorlog.txt
    echo
    nice vcgencmd measure_temp
    nice vcgencmd get_throttled
    echo >>/boot/errorlog.txt
    nice vcgencmd measure_volts >>/boot/errorlog.txt
    nice vcgencmd measure_temp >>/boot/errorlog.txt
    nice vcgencmd get_throttled >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt
    nice vcgencmd get_config int >>/boot/errorlog.txt

    nice /root/wifibroadcast_misc/raspi2png -p /boot/errorlog.png
    echo >>/boot/errorlog.txt
    nice dmesg >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt

    nice cat /etc/modprobe.d/rt2800usb.conf >> /boot/errorlog.txt
    nice cat /etc/modprobe.d/ath9k_htc.conf >> /boot/errorlog.txt
    nice cat /etc/modprobe.d/ath9k_hw.conf >> /boot/errorlog.txt

    echo >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt
    nice cat /boot/wifibroadcast-1.txt | egrep -v "^(#|$)" >> /boot/errorlog.txt
    echo >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt
    nice cat /boot/osdconfig.txt | egrep -v "^(//|$)" >> /boot/errorlog.txt
    echo >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt
    nice cat /boot/joyconfig.txt | egrep -v "^(//|$)" >> /boot/errorlog.txt
    echo >>/boot/errorlog.txt
    echo >>/boot/errorlog.txt
    nice cat /boot/apconfig.txt | egrep -v "^(#|$)" >> /boot/errorlog.txt

    sync
    nice mount -o remount,ro /boot
}

function wbclogger_function {
    # Waiting until video is running ...
    VIDEORXRUNNING=0
    while [ $VIDEORXRUNNING -ne 1 ]; do
		VIDEORXRUNNING=`pidof $DISPLAY_PROGRAM | wc -w`
		sleep 1
    done
	
    echo
	
    sleep 5
	
    nice /root/wifibroadcast/rssilogger /wifibroadcast_rx_status_0 >> /wbc_tmp/videorssi.csv &
    nice /root/wifibroadcast/rssilogger /wifibroadcast_rx_status_1 >> /wbc_tmp/telemetrydownrssi.csv &
    nice /root/wifibroadcast/syslogger /wifibroadcast_rx_status_sysair >> /wbc_tmp/system.csv &

    if [ "$TELEMETRY_UPLINK" != "disabled" ]; then
		nice /root/wifibroadcast/rssilogger /wifibroadcast_rx_status_uplink >> /wbc_tmp/telemetryuprssi.csv &
    fi
    if [ "$RC" != "disabled" ]; then
		nice /root/wifibroadcast/rssilogger /wifibroadcast_rx_status_rc >> /wbc_tmp/rcrssi.csv &
    fi

    if [ "$DEBUG" == "Y" ]; then
		nice /root/wifibroadcast/wifibackgroundscan $NICS >> /wbc_tmp/wifibackgroundscan.csv &
    fi
    sleep 365d
}

function pause_while {
        if [ -f "/tmp/pausewhile" ]; then
	    PAUSE=1
	        while [ $PAUSE -ne 0 ]; do
		    if [ ! -f "/tmp/pausewhile" ]; then
	    	        PAUSE=0
		    fi
		    sleep 1
		done
	fi
}


function detect_nics {
	tmessage "Setting up wifi cards ... "
	echo

	# set reg domain to DE to allow channel 12 and 13 for hotspot
	iw reg set DE

	NUM_CARDS=-1
	NICSWL=`ls /sys/class/net | nice grep wlan`

	for NIC in $NICSWL
	do
	    # set MTU to 2304
	    ifconfig $NIC mtu 2304
	    # re-name wifi interface to MAC address
	    NAME=`cat /sys/class/net/$NIC/address`
	    ip link set $NIC name ${NAME//:}
	    let "NUM_CARDS++"
	    #sleep 0.1
	done

	if [ "$NUM_CARDS" == "-1" ]; then
	    echo "ERROR: No wifi cards detected"
	    collect_errorlog
	    sleep 365d
	fi

    if [ "$CAM" == "0" ]; then # only do relay/hotspot stuff if RX
	    # get wifi hotspot card out of the way
	    if [ "$WIFI_HOTSPOT" == "Y" ]; then
			if [ "$WIFI_HOTSPOT_NIC" != "internal" ]; then
				# only configure it if it's there
				if ls /sys/class/net/ | grep -q $WIFI_HOTSPOT_NIC; then
					tmessage -n "Setting up $WIFI_HOTSPOT_NIC for Wifi Hotspot operation.. "
					ip link set $WIFI_HOTSPOT_NIC name wifihotspot0
					ifconfig wifihotspot0 192.168.2.1 up
					tmessage "done!"
					let "NUM_CARDS--"
				else
					tmessage "Wifi Hotspot card $WIFI_HOTSPOT_NIC not found!"
					sleep 0.5
				fi
			else
				# only configure it if it's there
				if ls /sys/class/net/ | grep -q intwifi0; then
					tmessage -n "Setting up intwifi0 for Wifi Hotspot operation.. "
					ip link set intwifi0 name wifihotspot0
					ifconfig wifihotspot0 192.168.2.1 up
					tmessage "done!"
				else
					tmessage "Pi3 Onboard Wifi Hotspot card not found!"
					sleep 0.5
				fi
			fi
	    fi
		
	    # get relay card out of the way
	    if [ "$RELAY" == "Y" ]; then
			# only configure it if it's there
			if ls /sys/class/net/ | grep -q $RELAY_NIC; then
				ip link set $RELAY_NIC name relay0
				prepare_nic relay0 $RELAY_FREQ
				let "NUM_CARDS--"
			else
				tmessage "Relay card $RELAY_NIC not found!"
				sleep 0.5
			fi
	    fi
	fi

    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`
#	echo "NICS: $NICS"

	if [ "$TXMODE" != "single" ]; then
	    for i in $(eval echo {0..$NUM_CARDS})
	    do
	        if [ "$CAM" == "0" ]; then
				prepare_nic ${MAC_RX[$i]} ${FREQ_RX[$i]}
	        else
				prepare_nic ${MAC_TX[$i]} ${FREQ_TX[$i]}
    		fi
			
			sleep 0.1
	    done
	else
	    # check if auto scan is enabled, if yes, set freq to 0 to let prepare_nic know not to set channel
	    if [ "$FREQSCAN" == "Y" ] && [ "$CAM" == "0" ]; then
			for NIC in $NICS
			do
				prepare_nic $NIC 2484
				sleep 0.1
			done
			
			# make sure check_alive function doesnt restart hello_video while we are still scanning for channel
			touch /tmp/pausewhile
			/root/wifibroadcast/rx -p 0 -d 1 -b $VIDEO_BLOCKS -r $VIDEO_FECS -f $VIDEOBLOCKLENGTH $NICS >/dev/null &
			sleep 0.5
			
			echo
			echo -n "Please wait, scanning for TX ..."
			FREQ=0

			if iw list | nice grep -q 5180; then # cards support 5G and 2.4G
				FREQCMD="/root/wifibroadcast/channelscan 245 $NICS"
			else
				if iw list | nice grep -q 2312; then # cards support 2.3G and 2.4G
					FREQCMD="/root/wifibroadcast/channelscan 2324 $NICS"
				else # cards support only 2.4G
					FREQCMD="/root/wifibroadcast/channelscan 24 $NICS"
				fi
			fi

			while [ $FREQ -eq 0 ]; do
				FREQ=`$FREQCMD`
			done

			echo "found on $FREQ MHz"
			echo
			ps -ef | nice grep "rx -p 0" | nice grep -v grep | awk '{print $2}' | xargs kill -9
			for NIC in $NICS
			do
				echo -n "Setting frequency on $NIC to $FREQ MHz.. "
				iw dev $NIC set freq $FREQ
				echo "done."
				sleep 0.1
			done
			
			# all done
			rm /tmp/pausewhile
	    else
			for NIC in $NICS
			do
				prepare_nic $NIC $FREQ
				sleep 0.1
			done
	    fi
	fi

	touch /tmp/nics_configured # let other processes know nics are setup and ready
}