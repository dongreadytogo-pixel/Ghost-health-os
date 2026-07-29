-- ============================================================
-- โปรแกรมแยกงานข่าว
-- ------------------------------------------------------------
-- เขียนใหม่ทั้งหมดจากหลักฐานในไฟล์บันทึกของเครื่องจริง
--
-- สามอย่างที่พิสูจน์แล้วว่าใช้ไม่ได้ ตัดออกหมดแล้ว
--
-- 1. การพิมพ์ตัวอักษรแทนผู้ใช้
--    บันทึกบรรทัดที่ 42 ชื่อ ghostexport กลายเป็น ฟฟฟฟฟฟฟฟฟฟฟ
--    เพราะแป้นพิมพ์ตอนนั้นเป็นภาษาไทย
--    สรุป จะพิมพ์อังกฤษหรือไทยก็เพี้ยนได้ทั้งคู่ ห้ามพิมพ์เด็ดขาด
--
-- 2. การบังคับที่เซฟด้วยคำสั่งไปที่โฟลเดอร์
--    ลองหลายรอบ ไฟล์ยังไปตกที่ F บ้าง Applications บ้าง
--    สรุป บังคับไม่ได้จริง เลิกฝืน
--
-- 3. การเรียกดูหน้าต่างขณะ Final Cut Pro ทำงานหนัก
--    บันทึกลงท้ายด้วย AppleEvent timed out ทุกครั้ง
--    นั่นคือสาเหตุที่หยุดหลังก้อนแรก
--    สรุป ทุกคำสั่งต้องมีเวลาจำกัด ห้ามรอไม่มีที่สิ้นสุด
--
-- แนวทางใหม่
-- ปล่อยให้ Final Cut Pro เซฟตรงไหนก็ได้ ไม่ยุ่งกับหน้าต่างเซฟเลย
-- แล้วเราตามไปเก็บไฟล์มาไว้ในโฟลเดอร์ที่ผู้ใช้เลือกทีหลัง
-- การย้ายไฟล์ควบคุมได้ 100 เปอร์เซ็นต์ ไม่ต้องพึ่งการกดปุ่ม
-- ============================================================

property appTitle : "แยกงานข่าว"
property fcpName : "Final Cut Pro"
-- ทุกคำสั่งที่คุยกับ Final Cut Pro ต้องมีเวลาจำกัดเสมอ
property uiTimeout : 12
-- ของที่มีเฉพาะในหน้าต่างของ Share ใช้เป็นตัวชี้ว่านี่คือหน้าต่างนั้น
property shareMarkers : {"Next…", "Next...", "Add Audio Track"}

global resourcesPath
global workPath
global prefsPath
global logPath
global statusPath
global channelsPath


on run argv
	if (count of argv) > 0 then
		set resourcesPath to item 1 of argv
	else
		set resourcesPath to (do shell script "dirname " & quoted form of (POSIX path of (path to me)))
	end if
	set workPath to (do shell script "mkdir -p ~/Library/Caches/fcpx-news-export && echo ~/Library/Caches/fcpx-news-export")
	set prefsPath to workPath & "/โฟลเดอร์ล่าสุด.txt"
	set logPath to workPath & "/บันทึกการทำงาน.txt"
	set statusPath to workPath & "/สถานะล่าสุด.txt"
	set channelsPath to workPath & "/จำนวนช่องเสียง.txt"
	logLine("===== เริ่มรอบใหม่ " & ((current date) as string) & " =====")
	showMainMenu()
end run


-- ============================================================
-- การบอกสถานะ
-- ------------------------------------------------------------
-- ผู้ใช้ต้องรู้ตลอดว่าโปรแกรมกำลังทำอะไรอยู่
-- เวลาเงียบหายไปจะได้ไม่ต้องเดาว่าค้างหรือกำลังทำงาน
-- ============================================================







on say(stepText)
	-- บันทึกลงไฟล์ และแจ้งเตือนบนหน้าจอแบบไม่ขวางการทำงาน
	logLine(stepText)
	try
		do shell script "echo " & quoted form of stepText & " > " & quoted form of statusPath
	end try
	try
		display notification stepText with title appTitle
	end try
end say


on logLine(theText)
	try
		set stamp to do shell script "date +%H:%M:%S"
		do shell script "echo " & quoted form of ("[" & stamp & "] " & theText) & ¬
			" >> " & quoted form of logPath
	end try
end logLine


-- ============================================================
-- หน้าจอหลัก
-- ============================================================

on showMainMenu()
	repeat
		activate
		set choice to button returned of (display dialog ¬
			"เปิดงานข่าวใน Final Cut Pro" & return & ¬
			"แล้วคลิกที่ชื่องานนั้นหนึ่งครั้ง" & return & return & ¬
			"จากนั้นกดปุ่ม เอ็กพอร์ต" & return & return & ¬
			"โปรแกรมจะแยกทุกก้อน สั่งเอ็กพอร์ต" & return & ¬
			"แล้วเก็บไฟล์มาไว้ในโฟลเดอร์ที่คุณเลือกให้เอง" ¬
			buttons {"ปิดโปรแกรม", "เมนูอื่น", "เอ็กพอร์ต"} ¬
			default button "เอ็กพอร์ต" with title appTitle)

		if choice is "ปิดโปรแกรม" then
			logLine("ผู้ใช้ปิดโปรแกรม")
			return
		else if choice is "เมนูอื่น" then
			showOtherMenu()
		else
			runWorkflow()
		end if
	end repeat
end showMainMenu


on showOtherMenu()
	--
	-- ใช้รายการให้เลือกแทนปุ่ม เพราะปุ่มในกล่องข้อความมีได้มากสุดสามปุ่ม
	-- เมนูนี้มีมากกว่าสามหัวข้อแล้ว และจะเพิ่มอีกในอนาคต
	-- รายการให้เลือกจึงขยายได้เรื่อย ๆ โดยไม่ต้องรื้อโครงสร้าง
	--
	repeat
		-- สร้างรายการใหม่ทุกรอบ เพื่อให้ตัวเลขที่โชว์ตรงกับค่าล่าสุดเสมอ
		set menuItems to {¬
			"สร้างแทร็กเสียง  ให้โปรแกรมกด Add Audio Track ให้ครบสามแทร็ก", ¬
			"ตั้งค่า Roles  เปิดหน้าต่าง MXF-50 ให้คุณตั้งเอง ครั้งเดียว", ¬
			"ดูค่าที่ตั้งไว้  อ่านค่า Roles ที่เครื่องนี้บันทึกไว้ในไฟล์", ¬
			"จำค่านี้ไว้  ถ่ายสำเนาค่าที่ตั้งถูกแล้ว เก็บไว้ใช้ทีหลัง", ¬
			"ใส่ค่าที่จำไว้กลับ  ใช้เมื่อค่า Roles เปลี่ยนไปเอง", ¬
			"ตรวจเสียง  เตือนเมื่อก้อนไหนมีเสียงน้อยกว่า " & requiredChannels() & " Role", ¬
			"แก้ปัญหา  ดูบันทึก และเก็บไฟล์ที่ตกค้าง"}
		activate
		set picked to (choose from list menuItems ¬
			with title appTitle ¬
			with prompt ("เมนูเพิ่มเติม" & return & "เลือกหนึ่งข้อแล้วกดตกลง") ¬
			OK button name "ตกลง" cancel button name "กลับ" ¬
			without multiple selections allowed and empty selection allowed)
		if picked is false then return

		set choice to item 1 of picked
		if choice starts with "สร้างแทร็กเสียง" then
			runBuildRolesLayout()
		else if choice starts with "ตั้งค่า Roles" then
			primeRolesSetting()
		else if choice starts with "ดูค่าที่ตั้งไว้" then
			reportRolesSettings()
		else if choice starts with "จำค่านี้ไว้" then
			rememberRolesSettings()
		else if choice starts with "ใส่ค่าที่จำไว้กลับ" then
			restoreRolesSettings()
		else if choice starts with "ตรวจเสียง" then
			askRequiredChannels()
		else
			showTroubleMenu()
		end if
	end repeat
end showOtherMenu


on showTroubleMenu()
	repeat
		activate
		set choice to button returned of (display dialog ¬
			"แก้ปัญหา" & return & return & ¬
			"เก็บไฟล์ที่ตกค้าง  ใช้เมื่อรอบก่อนหยุดกลางคัน" & return & ¬
			"                  จะไปตามเก็บไฟล์มาให้ครบ" & return & return & ¬
			"ดูบันทึก          ไฟล์บอกว่าโปรแกรมทำอะไรไปบ้าง" ¬
			buttons {"กลับ", "เก็บไฟล์ที่ตกค้าง", "ดูบันทึก"} ¬
			default button "กลับ" with title appTitle)
		if choice is "กลับ" then return
		if choice is "ดูบันทึก" then
			showLog()
		else
			collectLeftovers()
		end if
	end repeat
end showTroubleMenu


on putOnDesktop(sourcePath, niceName)
	--
	-- คัดลอกไฟล์ไปวางไว้บนหน้าจอ Desktop แล้วเปิด Finder ให้เห็น
	--
	-- ทำไมต้องทำแบบนี้
	-- ไฟล์ของโปรแกรมเก็บอยู่ในโฟลเดอร์ Library ซึ่ง macOS ซ่อนเอาไว้
	-- ต่อให้เปิด Finder ให้แล้ว ผู้ใช้ก็ยังลากไปส่งต่อได้ยาก
	-- และถ้าปิดหน้าต่างนั้นไป ก็หากลับเข้าไปเองแทบไม่ได้เลย
	--
	-- ย้ายมาวางบนหน้าจอ ลากไปใส่ช่องแชทได้ทันที เห็นด้วยตาตลอดเวลา
	-- คืนค่าเป็นที่อยู่ใหม่ หรือคืนค่าว่างเมื่อคัดลอกไม่สำเร็จ
	--
	try
		set desktopPath to (do shell script "echo $HOME") & "/Desktop/" & niceName
		do shell script "cp " & quoted form of sourcePath & " " & quoted form of desktopPath
		try
			do shell script "open -R " & quoted form of desktopPath
		end try
		logLine("วางไฟล์ไว้บนหน้าจอแล้ว " & desktopPath)
		return desktopPath
	on error e
		logLine("วางไฟล์บนหน้าจอไม่สำเร็จ " & e)
		return ""
	end try
end putOnDesktop


on showLog()
	set onDesktop to putOnDesktop(logPath, "บันทึกการทำงาน.txt")
	if onDesktop is "" then
		activate
		display dialog "ยังไม่มีบันทึก ลองกดปุ่ม เอ็กพอร์ต ก่อนหนึ่งครั้ง" ¬
			buttons {"ปิด"} default button 1 with title appTitle
		return
	end if
	activate
	display dialog ¬
		"วางไฟล์ไว้บนหน้าจอแล้ว" & return & return & ¬
		"ชื่อไฟล์  บันทึกการทำงาน.txt" & return & return & ¬
		"ลากไฟล์นั้นไปวางในช่องแชทได้เลย" ¬
		buttons {"ปิด"} default button 1 with title appTitle
end showLog


on dumpWindowTree(windowName)
	--
	-- จดโครงสร้างของหน้าต่างลงบันทึกให้ครบ
	--
	-- ทำไมต้องมี
	-- ผู้พัฒนาไม่มี Final Cut Pro จึงมองไม่เห็นว่าช่อง Roles as
	-- ถูกวางซ้อนอยู่ในชั้นไหน ที่ผ่านมาจึงต้องเดา และเดาผิดหลายรอบ
	-- ตัวนี้จะจดของทุกชิ้นพร้อมชั้นที่มันอยู่ ทำให้เลิกเดาได้ถาวร
	logLine("---- เริ่มจดโครงสร้างหน้าต่าง " & windowName & " ----")
	try
		with timeout of 30 seconds
			tell application "System Events"
				tell process fcpName
					if not (exists window windowName) then
						my logLine("ไม่มีหน้าต่างชื่อนี้ หน้าต่างที่มีคือ " & ((name of every window) as string))
						return
					end if
					tell window windowName
						repeat with a in UI elements
							set aClass to (class of a) as string
							set aName to ""
							try
								set aName to (name of a) as string
							end try
							set aValue to ""
							try
								set aValue to (value of a) as string
							end try
							my logLine("ชั้น1 " & aClass & " ชื่อ[" & aName & "] ค่า[" & aValue & "]")

							repeat with b in UI elements of a
								set bClass to (class of b) as string
								set bName to ""
								try
									set bName to (name of b) as string
								end try
								set bValue to ""
								try
									set bValue to (value of b) as string
								end try
								my logLine("  ชั้น2 " & bClass & " ชื่อ[" & bName & "] ค่า[" & bValue & "]")

								repeat with c in UI elements of b
									set cClass to (class of c) as string
									set cName to ""
									try
										set cName to (name of c) as string
									end try
									set cValue to ""
									try
										set cValue to (value of c) as string
									end try
									my logLine("    ชั้น3 " & cClass & " ชื่อ[" & cName & "] ค่า[" & cValue & "]")
								end repeat
							end repeat
						end repeat
					end tell
				end tell
			end tell
		end timeout
	on error e
		logLine("จดโครงสร้างไม่สำเร็จ " & e)
	end try
	logLine("---- จบการจดโครงสร้าง ----")
end dumpWindowTree


on logPresetLocations()
	-- หาไฟล์ preset ของ Roles ที่ผู้ใช้บันทึกไว้
	-- ในเมนูมีคำสั่ง Reveal User Presets in Finder แปลว่ามันเป็นไฟล์จริงในเครื่อง
	-- ถ้ารู้ตำแหน่ง อาจตั้งค่าได้โดยไม่ต้องพึ่งการกดปุ่มเลย
	try
		set found to do shell script ¬
			"find ~/Library/Application\\ Support/ProApps ~/Library/Containers/com.apple.FinalCut/Data/Library/Application\\ Support " & ¬
			"-maxdepth 4 -iname '*preset*' -o -maxdepth 4 -iname '*role*' 2>/dev/null | head -40"
		if found is "" then
			logLine("ไม่พบไฟล์ preset ในตำแหน่งที่คาดไว้")
		else
			logLine("ไฟล์ที่น่าจะเป็น preset")
			logLine(found)
		end if
	on error e
		logLine("หาไฟล์ preset ไม่สำเร็จ " & e)
	end try
	try
		set folders to do shell script "ls ~/Library/Application\\ Support/ProApps 2>/dev/null"
		logLine("ในโฟลเดอร์ ProApps มี " & folders)
	end try
end logPresetLocations


-- ============================================================
-- ค่า Roles ที่เก็บอยู่ในไฟล์ของเครื่อง
-- ------------------------------------------------------------
-- ช่อง Roles as เป็นปุ่มบนหน้าจอของ Final Cut Pro
-- เราสั่งให้เครื่องกดปุ่มนั้นแทนคนไม่สำเร็จสักที
-- แต่ค่าที่ตั้งไว้ไม่ได้อยู่แค่บนหน้าจอ มันถูกเขียนลงไฟล์จริงในเครื่อง
--
-- สามข้อนี้จึงเข้าไปทางไฟล์แทนทางปุ่ม
-- ดูค่าที่ตั้งไว้    อ่านไฟล์มาแสดงว่าตอนนี้ค่าเป็นอะไร
-- จำค่านี้ไว้       ถ่ายสำเนาไฟล์ทั้งชุดเก็บไว้ตอนที่ค่ายังถูก
-- ใส่ค่าที่จำไว้กลับ  เอาสำเนาใส่คืน เมื่อค่าถูกเปลี่ยนไป
--
-- ข้อดีคือเราไม่ต้องรู้เลยว่าข้างในไฟล์เขียนอะไรไว้ตรงไหน
-- ขอแค่ตั้ง 3 Stereo ด้วยมือให้ถูกหนึ่งครั้ง แล้วสั่งให้จำ
-- เป็นการคัดลอกไฟล์ธรรมดา จึงตรงเป๊ะเสมอ
-- ============================================================

on rolesTool(arguments)
	-- เรียกเครื่องมืออ่านค่า Roles คืนค่าเป็นข้อความที่มันพิมพ์ออกมา
	return do shell script "/usr/bin/env python3 " & ¬
		quoted form of (resourcesPath & "/tools/roles_presets.py") & " " & arguments
end rolesTool


on reportRolesSettings()
	set reportPath to workPath & "/ค่า Roles ในเครื่อง.txt"
	try
		rolesTool("report --out " & quoted form of reportPath)
	on error e
		activate
		display dialog "อ่านค่าไม่สำเร็จ" & return & return & e ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle
		logLine("อ่านค่า Roles ไม่สำเร็จ " & e)
		return
	end try

	-- ดึงเฉพาะบรรทัดที่มีคำว่า Stereo มาโชว์ให้เห็นทันที
	-- เพราะรายงานเต็มยาวเกินกว่าจะอ่านในกล่องข้อความ
	set highlights to ""
	try
		set highlights to do shell script ¬
			"grep -i stereo " & quoted form of reportPath & " | head -12"
	end try

	logLine("เขียนรายงานค่า Roles ไว้ที่ " & reportPath)
	if highlights is "" then
		set summary to "ยังไม่เจอค่าที่มีคำว่า Stereo ในไฟล์ตั้งค่า" & return & ¬
			"แปลว่าเครื่องนี้อาจเก็บค่าไว้คนละที่กับที่เราคาด" & return & return & ¬
			"กรุณาส่งไฟล์รายงานกลับมาให้ผมดู"
	else
		set summary to "ค่าที่เครื่องนี้บันทึกไว้" & return & return & highlights
	end if

	set onDesktop to putOnDesktop(reportPath, "ค่า Roles ในเครื่อง.txt")
	activate
	if onDesktop is "" then
		display dialog summary & return & return & ¬
			"ไฟล์รายงานอยู่ที่" & return & reportPath ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle
	else
		display dialog summary & return & return & ¬
			"วางไฟล์ไว้บนหน้าจอแล้ว" & return & ¬
			"ชื่อไฟล์  ค่า Roles ในเครื่อง.txt" & return & return & ¬
			"ลากไฟล์นั้นไปวางในช่องแชทได้เลย" ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle
	end if
end reportRolesSettings


on rememberRolesSettings()
	activate
	set answer to button returned of (display dialog ¬
		"จำค่า Roles ที่ตั้งไว้ตอนนี้" & return & return & ¬
		"ก่อนกดต่อ กรุณาตรวจว่าตอนนี้ Roles as เป็น 3 Stereo แล้วจริง" & return & ¬
		"เพราะโปรแกรมจะจำสภาพปัจจุบันไว้ทั้งชุด" & return & return & ¬
		"ถ้าค่ายังไม่ถูก ให้กลับไปที่ ตั้งค่า Roles ก่อน" ¬
		buttons {"ยกเลิก", "จำไว้เลย"} default button "จำไว้เลย" with title appTitle)
	if answer is "ยกเลิก" then return

	try
		set copied to rolesTool("snapshot " & quoted form of "ค่ามาตรฐาน")
	on error e
		activate
		display dialog "จำค่าไม่สำเร็จ" & return & return & e ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle
		logLine("จำค่า Roles ไม่สำเร็จ " & e)
		return
	end try

	logLine("จำค่า Roles ไว้แล้ว " & copied & " ไฟล์")
	activate
	display dialog "จำไว้แล้ว " & copied & " ไฟล์" & return & return & ¬
		"ต่อไปถ้าค่า Roles เปลี่ยนไปเอง" & return & ¬
		"ให้มาที่เมนูนี้แล้วเลือก ใส่ค่าที่จำไว้กลับ" ¬
		buttons {"ตกลง"} default button "ตกลง" with title appTitle
end rememberRolesSettings


on restoreRolesSettings()
	--
	-- Final Cut Pro อ่านไฟล์ตั้งค่าตอนเปิดโปรแกรม และเขียนทับตอนปิด
	-- ถ้าใส่ค่าคืนขณะที่มันเปิดอยู่ ค่าที่ใส่จะถูกเขียนทับทิ้งทันที
	-- จึงต้องให้ปิด Final Cut Pro ก่อน แล้วค่อยเปิดใหม่ทีหลัง
	--
	activate
	set answer to button returned of (display dialog ¬
		"ใส่ค่า Roles ที่จำไว้กลับ" & return & return & ¬
		"ต้องปิด Final Cut Pro ก่อน" & return & ¬
		"เพราะถ้ายังเปิดอยู่ มันจะเขียนทับค่าที่เราใส่คืน" & return & return & ¬
		"ปิด Final Cut Pro แล้วค่อยกด ใส่ค่าคืน" ¬
		buttons {"ยกเลิก", "ใส่ค่าคืน"} default button "ใส่ค่าคืน" with title appTitle)
	if answer is "ยกเลิก" then return

	try
		-- ห้ามตั้งชื่อตัวแปรว่า result เพราะ AppleScript จองคำนั้นไว้ใช้เอง
		set outcome to rolesTool("restore " & quoted form of "ค่ามาตรฐาน")
		logLine("ใส่ค่า Roles กลับ " & outcome)
		activate
		display dialog outcome & return & return & ¬
			"เปิด Final Cut Pro ขึ้นมาใหม่ได้เลย" ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle
	on error e
		logLine("ใส่ค่า Roles กลับไม่สำเร็จ " & e)
		activate
		display dialog "ใส่ค่าคืนไม่สำเร็จ" & return & return & e & return & return & ¬
			"ถ้าข้อความบอกว่า Final Cut Pro ยังเปิดอยู่" & return & ¬
			"ให้ปิดโปรแกรมนั้นก่อนแล้วลองใหม่" ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle
	end try
end restoreRolesSettings


on openShareWindow(destinationName)
	--
	-- เปิดหน้าต่างของปลายทางขึ้นมาเฉย ๆ โดยยังไม่เอ็กพอร์ตอะไร
	-- คืนค่า true เมื่อหน้าต่างโผล่แล้ว
	--
	if menuState("File", "Share") is "disabled" then
		activate
		display dialog ¬
			"เมนู Share กดไม่ได้" & return & return & ¬
			"ให้คลิกเลือกงานในหน้าต่าง Browser ไว้หนึ่งชิ้นก่อน" & return & ¬
			"แล้วลองใหม่อีกครั้ง" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
		return false
	end if

	try
		with timeout of uiTimeout seconds
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					delay 0.3
					set fileMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "File")
					set shareItem to (first menu item of fileMenu whose name starts with "Share")
					click (first menu item of menu 1 of shareItem whose name starts with destinationName)
				end tell
			end tell
		end timeout
	on error e
		logLine("เปิดหน้าต่าง " & destinationName & " ไม่สำเร็จ " & e)
		activate
		display dialog "เปิดหน้าต่าง " & destinationName & " ไม่สำเร็จ" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
		return false
	end try

	-- รอด้วยการหาจากของข้างใน ไม่ใช่จากชื่อ
	-- เพราะบันทึกจริงบอกว่าบางครั้งหน้าต่างนี้เป็นแผ่นซ้อนบนหน้าต่างหลัก
	-- และบางครั้งชื่อของมันเป็นค่าว่าง การรอชื่อจึงรอเก้อ
	repeat with waited from 1 to 15
		if my findShareWindow() is not 0 then return true
		delay 1
	end repeat
	logLine("รอหน้าต่างของ " & destinationName & " จนครบเวลาแล้วไม่เจอ")
	return false
end openShareWindow


on runBuildRolesLayout()
	--
	-- สร้างแทร็กเสียงสามแทร็กให้เสร็จในครั้งเดียว โดยไม่เอ็กพอร์ตไฟล์ใด ๆ
	--
	-- เมนูนี้มีไว้ให้ทดสอบได้เร็ว
	-- ถ้าต้องรอเอ็กพอร์ตจริงทุกครั้งเพื่อดูว่าตั้งได้ไหม จะเสียเวลามาก
	--
	if not ensureFinalCutRunning() then return
	if not ensureAccessibility() then return

	activate
	display dialog ¬
		"สร้างแทร็กเสียงให้ MXF-50" & return & return & ¬
		"โปรแกรมจะเปิดหน้าต่าง MXF-50 แล้วกดปุ่ม Add Audio Track" & return & ¬
		"จนได้ครบสามแทร็ก แต่ละแทร็กตั้ง Channels เป็น Stereo" & return & ¬
		"แล้วใส่ All Dialogue  All Effects  All Music ให้ทุกแทร็ก" & return & return & ¬
		"ไม่มีการเอ็กพอร์ตไฟล์ใด ๆ ทั้งสิ้น" & return & return & ¬
		"ต้องเลือกงานในหน้าต่าง Browser ไว้ก่อนหนึ่งชิ้น" ¬
		buttons {"เริ่มเลย"} default button 1 with title appTitle

	if not openShareWindow("MXF-50") then return

	set built to buildRolesLayout("MXF-50")

	-- ปิดหน้าต่างทิ้ง ไม่ต้องเอ็กพอร์ตอะไร
	pressButtons({"Cancel", "ยกเลิก"})
	delay 1

	activate
	if built then
		display dialog ¬
			"ตั้งแทร็กเสียงเรียบร้อยแล้ว" & return & return & ¬
			"ได้สามแทร็ก แทร็กละสองช่อง" & return & ¬
			"ปิดหน้าต่างให้แล้ว ไม่มีไฟล์ไหนถูกสร้าง" & return & return & ¬
			"Final Cut Pro มักจำค่านี้ไว้ให้" & return & ¬
			"ถ้าอยากให้แน่ใจ ให้กด จำค่านี้ไว้ ในเมนูเดิมอีกหนึ่งครั้ง" ¬
			buttons {"เข้าใจแล้ว"} default button 1 with title appTitle
	else
		display dialog ¬
			"ยังตั้งแทร็กเสียงไม่สำเร็จ" & return & return & ¬
			"ปิดหน้าต่างให้แล้ว ไม่มีไฟล์ไหนถูกสร้าง" & return & return & ¬
			"โปรแกรมจดผังหน้าต่างไว้ในบันทึกแล้ว" & return & ¬
			"กรุณาส่งไฟล์ บันทึกการทำงาน.txt กลับมาให้ผมดู" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
	end if
end runBuildRolesLayout


on primeRolesSetting()
	--
	-- เปิดหน้าต่าง MXF-50 ขึ้นมาเฉย ๆ เพื่อให้ผู้ใช้ตั้ง Roles as เป็น 3 Stereo
	--
	-- ทำไมต้องมีเมนูนี้
	-- ช่อง Roles as มีอยู่เฉพาะในหน้าต่างของ Share เท่านั้น
	-- ปกติหน้าต่างนี้จะโผล่ก็ต่อเมื่อกำลังจะเอ็กพอร์ตจริง
	-- ผู้ใช้จึงไม่มีจังหวะไหนเลยที่จะตั้งค่านี้ล่วงหน้าได้
	--
	-- เมนูนี้เปิดหน้าต่างนั้นขึ้นมาให้ตั้งค่าอย่างเดียว แล้วปิดทิ้ง
	-- ไม่มีการเอ็กพอร์ตไฟล์ใด ๆ เกิดขึ้น
	-- Final Cut Pro มักจำค่าที่ตั้งล่าสุดไว้ให้ รอบต่อ ๆ ไปจึงถูกต้องเอง

	if not ensureFinalCutRunning() then return
	if not ensureAccessibility() then return

	activate
	display dialog ¬
		"ตั้งค่า Roles ครั้งเดียว" & return & return & ¬
		"โปรแกรมจะเปิดหน้าต่าง MXF-50 ขึ้นมาให้" & return & ¬
		"ไม่มีการเอ็กพอร์ตไฟล์ใด ๆ ทั้งสิ้น" & return & return & ¬
		"ในหน้าต่างนั้นให้คุณ" & return & ¬
		"1. ไปที่แท็บ Roles" & return & ¬
		"2. ตั้งช่อง Roles as ให้เป็น 3 Stereo" & return & return & ¬
		"พอตั้งเสร็จ โปรแกรมจะรู้เองแล้วปิดหน้าต่างให้" & return & ¬
		"คุณไม่ต้องกดปุ่มอะไรบอกมันเลย" & return & return & ¬
		"ต้องเลือกงานในหน้าต่าง Browser ไว้ก่อนหนึ่งชิ้น" ¬
		buttons {"เปิดให้เลย"} default button 1 with title appTitle

	if not openShareWindow("MXF-50") then return

	openRolesTab("MXF-50")
	-- จดโครงสร้างจริงไว้เสมอ เพื่อให้ผู้พัฒนาเลิกเดาตำแหน่งช่อง Roles as
	dumpWindowTree("MXF-50")
	logPresetLocations()
	set startValue to findRolesPopupValue("MXF-50")
	logLine("ตั้งค่า Roles ครั้งเดียว ค่าเริ่มต้นคือ [" & startValue & "]")

	-- ลองตั้งให้เองก่อน ถ้าได้ก็จบเลย
	if startValue is not "3 Stereo" then
		clickRolesChoice("MXF-50", "3 Stereo")
	end if

	say("ตั้ง Roles as เป็น 3 Stereo ในหน้าต่างที่เปิดอยู่")
	try
		tell application "Final Cut Pro" to activate
	end try

	-- เฝ้าดูเงียบ ๆ ไม่ขวางการกดใด ๆ
	set didSet to false
	repeat with i from 1 to 90
		delay 2
		set nowValue to findRolesPopupValue("MXF-50")
		if nowValue is "3 Stereo" then
			set didSet to true
			exit repeat
		end if
		if nowValue is "" then exit repeat
		if i mod 15 is 0 then say("ยังรอให้ตั้ง 3 Stereo อยู่")
	end repeat

	-- ปิดหน้าต่างให้ ไม่ต้องเอ็กพอร์ตอะไร
	pressButtons({"Cancel", "ยกเลิก"})
	delay 1

	activate
	if didSet then
		logLine("ตั้งค่า Roles ครั้งเดียวสำเร็จ")
		display dialog ¬
			"ตั้งค่าเรียบร้อยแล้ว" & return & return & ¬
			"Roles as เป็น 3 Stereo แล้ว" & return & ¬
			"ปิดหน้าต่างให้แล้ว ไม่มีไฟล์ไหนถูกสร้าง" & return & return & ¬
			"Final Cut Pro มักจำค่านี้ไว้ให้" & return & ¬
			"รอบเอ็กพอร์ตต่อไปจึงน่าจะถูกต้องเอง" ¬
			buttons {"เข้าใจแล้ว"} default button 1 with title appTitle
	else
		logLine("ตั้งค่า Roles ครั้งเดียวไม่สำเร็จ")
		activate
		display dialog ¬
			"ยังไม่ได้ตั้งเป็น 3 Stereo" & return & return & ¬
			"ปิดหน้าต่างให้แล้ว ไม่มีไฟล์ไหนถูกสร้าง" & return & return & ¬
			"ลองใหม่ได้จากเมนูเดิม" ¬
			buttons {"ปิด"} default button 1 with title appTitle
	end if
end primeRolesSetting


on collectLeftovers()
	set namesFile to workPath & "/รายชื่อไฟล์.txt"
	try
		set totalFiles to (do shell script "grep -c . " & quoted form of namesFile) as integer
	on error
		activate
		activate
	display dialog ¬
			"ยังไม่มีรายชื่อไฟล์จากรอบก่อน" & return & ¬
			"ต้องกดเอ็กพอร์ตอย่างน้อยหนึ่งครั้งก่อน" ¬
			buttons {"ปิด"} default button 1 with title appTitle
		return
	end try
	set outFolder to chooseOutputFolder()
	if outFolder is "" then return
	monitorAndCollect(outFolder, namesFile, totalFiles)
end collectLeftovers


-- ============================================================
-- ลำดับการทำงาน
-- ============================================================

on runWorkflow()
	try
		if not ensureFinalCutRunning() then return
		if not ensureAccessibility() then return

		set outFolder to chooseOutputFolder()
		if outFolder is "" then return
		say("โฟลเดอร์ปลายทาง " & outFolder)

		set xmlPath to fetchTimeline(outFolder)
		if xmlPath is "" then return

		set gapSeconds to "0.2"
		repeat
			set reportText to runBrief(xmlPath, gapSeconds)
			activate
		set answer to button returned of (display dialog ¬
				reportText & return & return & "จำนวนก้อนถูกต้องไหม" ¬
				buttons {"ยกเลิก", "ปรับจำนวนก้อน", "ถูกต้อง ไปต่อ"} ¬
				default button "ถูกต้อง ไปต่อ" with title appTitle)
			if answer is "ยกเลิก" then return
			if answer is "ถูกต้อง ไปต่อ" then exit repeat
			set gapSeconds to askGapSeconds(gapSeconds)
			if gapSeconds is "" then return
		end repeat

		say("กำลังแยกก้อน")
		set splitPath to (workPath & "/แยกแล้ว.fcpxml")
		set eventName to "แยกงาน " & (do shell script "date +%d-%m' '%H%M")
		runSplit(xmlPath, gapSeconds, splitPath, eventName)

		set namesFile to workPath & "/รายชื่อไฟล์.txt"
		do shell script "/usr/bin/env python3 " & quoted form of (resourcesPath & "/tools/fcpxml_segments.py") & ¬
			" " & quoted form of xmlPath & " --min-gap " & gapSeconds & " --names > " & quoted form of namesFile
		set totalFiles to (do shell script "grep -c . " & quoted form of namesFile) as integer
		say("แยกเสร็จ ต้องได้ทั้งหมด " & totalFiles & " ไฟล์")

		-- ตรวจเสียงก่อนเอ็กพอร์ต
		--
		-- ไฟล์ MXF-50 ต้องมีเสียงครบทุกช่อง
		-- แต่ Final Cut Pro สร้างช่องเสียงให้เฉพาะ Role ที่มีของอยู่จริงในก้อนนั้น
		-- ถ้าก้อนไหนไม่มีคลิปที่ใช้ Role ครบ ไฟล์ของก้อนนั้นก็จะขาดช่องไป
		-- ทั้งที่ตั้งค่าหน้าต่างเอ็กพอร์ตไว้ถูกต้องแล้ว
		--
		-- ตรวจตรงนี้จึงคุ้มมาก เพราะรู้ก่อนเสียเวลาเอ็กพอร์ตทั้งชุด
		if not checkAudioBeforeExport(xmlPath, gapSeconds) then return

		say("กำลังนำงานย่อยกลับเข้า Final Cut Pro")
		importTimeline(splitPath)

		activate
		activate
	display dialog ¬
			"กำลังจะสั่งเอ็กพอร์ต" & return & return & ¬
			"โปรแกรมจะสั่ง Share สองรอบ" & return & ¬
			"ปล่อยให้ Final Cut Pro เซฟที่ไหนก็ได้ ไม่ต้องสนใจ" & return & ¬
			"เดี๋ยวโปรแกรมจะตามไปเก็บไฟล์มาไว้ที่" & return & outFolder & return & return & ¬
			"ระหว่างนี้อย่าแตะเมาส์และคีย์บอร์ด" ¬
			buttons {"เริ่มเลย"} default button 1 with title appTitle

		-- ไม่ไปยุ่งกับการเลือกงานเลย
		--
		-- Final Cut Pro เลือกงานที่เพิ่งนำเข้าให้ทั้งหมดอยู่แล้ว
		-- ที่ผ่านมาโปรแกรมไปสั่งเลือกใหม่ ซึ่งอาจไปล้างการเลือกที่ถูกต้องทิ้ง
		-- แล้วเหลือแค่ชิ้นเดียว จึงได้ไฟล์มาก้อนเดียว
		--
		-- สั่ง Share สองรอบติดกันเลย ไม่ต้องรอไฟล์รอบแรกเสร็จ
		-- เพราะ Final Cut Pro รับงานเข้าคิวแล้วทยอยทำเองพร้อมกันได้
		shareTo("Export File", "ไฟล์ mov", "")
		shareTo("MXF-50", "ไฟล์ mxf", "3 Stereo")

		monitorAndCollect(outFolder, namesFile, totalFiles)
		say("จบรอบการทำงาน")

	on error errorMessage number errorNumber
		if errorNumber is -128 then return
		logLine("พังกลางทาง " & errorMessage)
		activate
		activate
	display dialog ¬
			"เกิดปัญหา" & return & return & errorMessage & return & return & ¬
			"ไฟล์ที่เอ็กพอร์ตไปแล้วยังอยู่ครบ ไม่หายไปไหน" & return & return & ¬
			"กดปุ่ม เมนูอื่น แล้วเลือก เก็บไฟล์ที่ตกค้าง" & return & ¬
			"โปรแกรมจะไปตามเก็บมาให้" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
	end try
end runWorkflow


-- ============================================================
-- ตรวจเสียงก่อนเอ็กพอร์ต
-- ------------------------------------------------------------
-- ไฟล์ MXF-50 ใช้ preset ชื่อ 3 Stereo
-- ได้สามแทร็ก แทร็กละสองช่อง รวมหกช่อง
-- และทั้งสามแทร็กรับ All Dialogue กับ All Effects กับ All Music เหมือนกัน
--
-- จำนวนแทร็กจึงมาจาก preset ไม่ได้มาจากเนื้อในของก้อน
-- ก้อนที่เสียงไม่ครบก็ยังได้สามแทร็กเหมือนเดิม แต่จะมีส่วนที่เงียบ
--
-- ที่ตรวจตรงนี้จึงไม่ใช่จำนวนแทร็ก แต่คือความเงียบที่ไม่ตั้งใจ
-- เพราะความเงียบที่ออกอากาศไปแล้ว แก้ทีหลังไม่ได้
-- ============================================================

on requiredChannels()
	-- จำนวน Role ของเสียงที่แต่ละก้อนต้องมี
	-- เก็บเป็นไฟล์เพื่อให้แก้ได้ในภายหลังโดยไม่ต้องแก้โปรแกรม
	try
		set saved to do shell script "cat " & quoted form of channelsPath
		if saved is not "" then return saved
	end try
	return "6"
end requiredChannels


on askRequiredChannels()
	-- ให้ผู้ใช้ตั้งเองว่าไฟล์ MXF ต้องมีกี่ช่องเสียง
	-- ห้องข่าวนี้ใช้หกช่องแยกกัน แต่ทำเป็นค่าตั้งไว้ เผื่องานอื่นใช้ไม่เท่ากัน
	activate
	try
		set answer to text returned of (display dialog ¬
			"แต่ละก้อนต้องมีเสียงกี่ Role" & return & return & ¬
			"ไฟล์ MXF-50 ใช้ preset ชื่อ 3 Stereo" & return & ¬
			"ได้สามแทร็ก แทร็กละสองช่อง รวมหกช่อง เสมอ" & return & return & ¬
			"ตัวเลขนี้ไม่ได้เปลี่ยนจำนวนแทร็กในไฟล์" & return & ¬
			"แต่ใช้เตือนว่าก้อนไหนเสียงหายไปจนอาจออกอากาศเงียบ" ¬
			default answer requiredChannels() ¬
			buttons {"ยกเลิก", "บันทึก"} default button "บันทึก" with title appTitle)
	on error number -128
		return
	end try

	set cleaned to do shell script "echo " & quoted form of answer & " | tr -cd '0-9'"
	if cleaned is "" or cleaned is "0" then
		activate
		display dialog "ต้องเป็นตัวเลขที่มากกว่าศูนย์" ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle
		return
	end if

	do shell script "echo " & quoted form of cleaned & " > " & quoted form of channelsPath
	logLine("ตั้งจำนวน Role ของเสียงเป็น " & cleaned)
	activate
	display dialog "บันทึกแล้ว แต่ละก้อนต้องมีเสียงอย่างน้อย " & cleaned & " Role" ¬
		buttons {"ตกลง"} default button "ตกลง" with title appTitle
end askRequiredChannels


on checkAudioBeforeExport(xmlPath, gapSeconds)
	set wanted to requiredChannels()
	set reportPath to workPath & "/ตรวจเสียง.txt"
	set summary to ""

	try
		-- ต่อท้ายด้วย true เพราะโปรแกรมตรวจจะคืนรหัส 1 เมื่อเจอก้อนที่เสียงไม่ครบ
		-- ซึ่งไม่ใช่ความผิดพลาด แต่เป็นผลการตรวจที่เราต้องการอ่าน
		set summary to do shell script "/usr/bin/env python3 " & ¬
			quoted form of (resourcesPath & "/tools/audio_audit.py") & " " & ¬
			quoted form of xmlPath & " --min-gap " & gapSeconds & ¬
			" --require " & wanted & " --brief 2>&1 || true"
		do shell script "/usr/bin/env python3 " & ¬
			quoted form of (resourcesPath & "/tools/audio_audit.py") & " " & ¬
			quoted form of xmlPath & " --min-gap " & gapSeconds & ¬
			" --require " & wanted & " > " & quoted form of reportPath & " 2>&1 || true"
	on error e
		logLine("ตรวจเสียงไม่สำเร็จ " & e)
		return true
	end try

	logLine("ผลตรวจเสียง " & summary)

	if summary starts with "เสียงครบ" then
		say(summary)
		return true
	end if

	-- เสียงไม่ครบ ต้องบอกให้เห็นชัด แต่ไม่ตัดสินใจแทนผู้ใช้
	-- บางวันงานอาจตั้งใจให้บางก้อนมีเสียงน้อยกว่าจริง ๆ
	activate
	set answer to button returned of (display dialog ¬
		"ตรวจเสียงแล้วพบว่าไม่ครบ" & return & return & summary & return & return & ¬
		"ไฟล์ยังได้สามแทร็กครบตาม preset 3 Stereo" & return & ¬
		"แต่ส่วนที่ไม่มีของ จะออกอากาศเป็นความเงียบ" & return & return & ¬
		"จะไปต่อ หรือหยุดไปแก้เสียงก่อน" ¬
		buttons {"ดูรายละเอียด", "หยุดก่อน", "ไปต่อ"} ¬
		default button "หยุดก่อน" with title appTitle with icon caution)

	if answer is "ไปต่อ" then return true
	if answer is "หยุดก่อน" then
		say("หยุดเพื่อไปแก้เสียงก่อน")
		return false
	end if

	putOnDesktop(reportPath, "ตรวจเสียง.txt")
	activate
	set answer to button returned of (display dialog ¬
		"วางไฟล์ไว้บนหน้าจอแล้ว ชื่อ ตรวจเสียง.txt" & return & ¬
		"ในนั้นบอกทีละก้อนว่าขาด Role ไหนบ้าง" ¬
		buttons {"หยุดก่อน", "ไปต่อ"} default button "หยุดก่อน" with title appTitle)
	if answer is "ไปต่อ" then return true
	say("หยุดเพื่อไปแก้เสียงก่อน")
	return false
end checkAudioBeforeExport


-- ============================================================
-- ตรวจความพร้อม
-- ============================================================

on ensureFinalCutRunning()
	set isRunning to false
	try
		with timeout of uiTimeout seconds
			tell application "System Events" to set isRunning to (exists process fcpName)
		end timeout
	end try
	if isRunning then return true
	activate
	display dialog ¬
		"ยังไม่ได้เปิด Final Cut Pro" & return & return & ¬
		"ให้เปิดโปรแกรมและเปิดงานข่าวค้างไว้ แล้วลองใหม่" ¬
		buttons {"ปิด"} default button 1 with title appTitle with icon caution
	return false
end ensureFinalCutRunning


on ensureAccessibility()
	try
		with timeout of uiTimeout seconds
			tell application "System Events"
				tell process fcpName to get name of menu bar 1
			end tell
		end timeout
		return true
	on error
		activate
		set answer to button returned of (display dialog ¬
			"ต้องเปิดสิทธิ์ให้โปรแกรมกดเมนูแทนคุณก่อน ทำครั้งเดียวจบ" & return & return & ¬
			"1. กดปุ่ม เปิดหน้าตั้งค่า" & return & ¬
			"2. หาชื่อ แยกงานข่าว แล้วเปิดสวิตช์ให้เป็นสีเขียว" & return & ¬
			"3. กลับมาเปิดโปรแกรมนี้ใหม่" ¬
			buttons {"ปิด", "เปิดหน้าตั้งค่า"} default button "เปิดหน้าตั้งค่า" ¬
			with title appTitle with icon caution)
		if answer is "เปิดหน้าตั้งค่า" then
			do shell script "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
		end if
		return false
	end try
end ensureAccessibility


on chooseOutputFolder()
	set startFolder to missing value
	try
		set lastFolder to (do shell script "cat " & quoted form of prefsPath)
		if lastFolder is not "" then set startFolder to (POSIX file lastFolder) as alias
	end try
	try
		if startFolder is missing value then
			set chosen to choose folder with prompt "เลือกโฟลเดอร์ที่จะเก็บไฟล์ mov และ mxf"
		else
			set chosen to choose folder with prompt "เลือกโฟลเดอร์ที่จะเก็บไฟล์ mov และ mxf" default location startFolder
		end if
	on error
		return ""
	end try
	set chosenPath to POSIX path of chosen
	if chosenPath ends with "/" then set chosenPath to text 1 thru -2 of chosenPath
	do shell script "echo " & quoted form of chosenPath & " > " & quoted form of prefsPath
	return chosenPath
end chooseOutputFolder


-- ============================================================
-- ไปเอาไทม์ไลน์ ไม่ยุ่งกับหน้าต่างเซฟเลย
-- ============================================================

on fetchTimeline(outFolder)
	set marker to workPath & "/เริ่มเมื่อ"
	do shell script "rm -f " & quoted form of marker & " && touch " & quoted form of marker

	if menuState("File", "Export XML") is "disabled" then
		activate
		set answer to button returned of (display dialog ¬
			"ยังไม่ได้เลือกงานข่าว" & return & return & ¬
			"ใน Final Cut Pro ให้คลิกที่ ชื่องาน หนึ่งครั้ง" & return & ¬
			"คลิกที่ตัวงานในหน้าต่าง Browser" & return & ¬
			"ไม่ใช่คลิกที่ Event หรือ Library" & return & return & ¬
			"คลิกเสร็จแล้วกดปุ่มข้างล่าง" ¬
			buttons {"ยกเลิก", "เลือกแล้ว"} default button "เลือกแล้ว" with title appTitle)
		if answer is "ยกเลิก" then return ""
	end if

	activate
	display dialog ¬
		"กำลังจะอ่านไทม์ไลน์" & return & return & ¬
		"จะมีหน้าต่างเซฟเด้งขึ้นมา โปรแกรมจะกดยืนยันเอง" & return & ¬
		"ไม่ต้องสนใจว่ามันเซฟไว้ที่ไหน" & return & return & ¬
		"ระหว่างนี้อย่าแตะเมาส์และคีย์บอร์ด" ¬
		buttons {"เริ่มเลย"} default button 1 with title appTitle

	say("กำลังสั่ง Final Cut Pro ส่งไทม์ไลน์ออกมา")
	clickMenu("File", "Export XML")
	if waitForSheet(15) then
		-- กดยืนยันอย่างเดียว ไม่แตะชื่อไฟล์ ไม่แตะที่เก็บ
		-- สองอย่างนั้นพิสูจน์แล้วว่าควบคุมไม่ได้ และทำให้พังทุกครั้ง
		pressButtons({"Save", "Export", "OK"})
		delay 1
		pressButtons({"Replace", "แทนที่"})
		say("กดยืนยันหน้าต่างเซฟแล้ว กำลังตามหาไฟล์")
	else
		logLine("หน้าต่างเซฟไม่โผล่")
	end if

	set foundPath to waitForTimeline(marker, outFolder, 25)
	if foundPath is not "" then
		say("ได้ไทม์ไลน์มาแล้ว")
		return foundPath
	end if

	activate
		set answer to button returned of (display dialog ¬
		"หาไฟล์ไทม์ไลน์ที่เพิ่งเซฟไม่เจอ" & return & return & ¬
		"กดปุ่ม ชี้ให้ดู แล้วเลือกไฟล์นั้น" ¬
		buttons {"ยกเลิก", "ชี้ให้ดู"} default button "ชี้ให้ดู" with title appTitle)
	if answer is "ยกเลิก" then return ""
	try
		set picked to POSIX path of (choose file with prompt "เลือกไฟล์ที่เพิ่งเซฟ")
		say("ผู้ใช้ชี้ไฟล์เอง")
		return picked
	on error
		return ""
	end try
end fetchTimeline


on waitForTimeline(marker, outFolder, maxTries)
	repeat with i from 1 to maxTries
		try
			set found to do shell script "/usr/bin/env python3 " & ¬
				quoted form of (resourcesPath & "/tools/find_recent.py") & ¬
				" " & quoted form of marker & " " & quoted form of outFolder
			if found is not "" then
				logLine("เจอไทม์ไลน์ที่ " & found)
				delay 1
				return found
			end if
		end try
		if i mod 8 is 0 then say("ยังตามหาไฟล์ไทม์ไลน์อยู่ ผ่านไป " & i & " วินาที")
		delay 1
	end repeat
	logLine("หาไทม์ไลน์ไม่เจอหลังจากลอง " & maxTries & " รอบ")
	return ""
end waitForTimeline


on importTimeline(splitPath)
	do shell script "open -a " & quoted form of "/Applications/Final Cut Pro.app" & ¬
		" " & quoted form of splitPath
	delay 3
	pressButtons({"Import", "OK", "นำเข้า"})
	delay 1
end importTimeline


-- ============================================================
-- สั่งเอ็กพอร์ต
-- ============================================================




on countPanelFields()
	-- นับช่องกรอกในหน้าต่างเซฟ โดยดูในกระบวนการที่ถือหน้าต่างจริง
	--
	-- ที่ผ่านมานับผิดที่ ไปนับในตัว Final Cut Pro ซึ่งไม่มีหน้าต่างเซฟอยู่เลย
	-- จึงได้ 0 ทุกครั้ง แล้วเข้าใจผิดว่าเลือกงานครบ ทั้งที่เลือกได้อันเดียว
	--
	-- ความหมายของผลลัพธ์
	--   0 ช่อง  ถามหาแค่โฟลเดอร์ แปลว่าเลือกงานได้หลายอัน ถูกต้อง
	--   มีช่อง  ถามชื่อไฟล์ด้วย แปลว่าเลือกได้อันเดียว จะได้ไฟล์ไม่ครบ
	set total to 0
	repeat with processName in panelProcesses()
		try
			with timeout of uiTimeout seconds
				tell application "System Events"
					tell process processName
						repeat with windowRef in windows
							try
								set total to total + (count of text fields of windowRef)
							end try
							repeat with sheetRef in sheets of windowRef
								try
									set total to total + (count of text fields of sheetRef)
								end try
							end repeat
						end repeat
					end tell
				end tell
			end timeout
		end try
	end repeat
	return total
end countPanelFields


on waitForWindowNamed(windowName, maxSeconds)
	--
	-- รอจนหน้าต่างชื่อที่ต้องการโผล่ขึ้นมาจริง
	--
	-- หลักฐานจากผลทดสอบบนเครื่องจริง
	-- หน้าต่างของ Share ชื่อตรงกับปลายทาง เช่น Export File หรือ MXF-50
	-- แต่ในรายการหน้าต่างมีหน้าต่างไม่มีชื่อปนอยู่ด้วยหลายอัน
	-- ที่ผ่านมาโปรแกรมใช้หน้าต่างที่หนึ่ง จึงไปโดนหน้าต่างเปล่าที่ไม่มีอะไรข้างใน
	-- และหน้าต่างจริงใช้เวลาโผล่ ถ้ารีบเข้าไปอ่านจะยังไม่มี
	repeat with i from 1 to maxSeconds
		try
			with timeout of uiTimeout seconds
				tell application "System Events"
					tell process fcpName
						if exists window windowName then
							my logLine("เจอหน้าต่างชื่อ " & windowName & " แล้ว")
							return true
						end if
					end tell
				end tell
			end timeout
		end try
		delay 1
	end repeat
	-- ยังไม่เจอ จดรายชื่อหน้าต่างทั้งหมดไว้ดู
	try
		with timeout of uiTimeout seconds
			tell application "System Events"
				tell process fcpName
					my logLine("รอหน้าต่าง " & windowName & " ไม่เจอ หน้าต่างที่มีคือ " & ((name of every window) as string))
				end tell
			end tell
		end timeout
	end try
	return false
end waitForWindowNamed


on findRolesPopupValue(destinationName)
	--
	-- อ่านค่าปัจจุบันของช่อง Roles as
	--
	-- ใช้หลักเดียวกับตอนเลือก คือหาช่องที่มีรายการ 3 Stereo อยู่ข้างใน
	-- ไม่อ้างอิงชนิดของช่องเลย เพราะเดาผิดมาหลายรอบแล้ว
	set foundValue to ""
	try
		with timeout of 25 seconds
			tell application "System Events"
				tell process fcpName
					if not (exists window destinationName) then return ""
					tell window destinationName
						repeat with a in UI elements
							set foundValue to my valueIfHas(a, "3 Stereo")
							if foundValue is not "" then return foundValue
							repeat with b in UI elements of a
								set foundValue to my valueIfHas(b, "3 Stereo")
								if foundValue is not "" then return foundValue
								repeat with c in UI elements of b
									set foundValue to my valueIfHas(c, "3 Stereo")
									if foundValue is not "" then return foundValue
									repeat with d in UI elements of c
										set foundValue to my valueIfHas(d, "3 Stereo")
										if foundValue is not "" then return foundValue
									end repeat
								end repeat
							end repeat
						end repeat
					end tell
				end tell
			end tell
		end timeout
	end try
	return ""
end findRolesPopupValue


on valueIfHas(elementRef, markerName)
	-- ถ้าของชิ้นนี้มีรายการชื่อ markerName อยู่ข้างใน แปลว่าเป็นช่อง Roles as
	-- ให้คืนค่าปัจจุบันของมันกลับไป ถ้าไม่ใช่ก็คืนค่าว่าง
	try
		tell application "System Events"
			set itemNames to name of every menu item of menu 1 of elementRef
			if itemNames contains markerName then
				return (value of elementRef) as string
			end if
		end tell
	end try
	return ""
end valueIfHas


on openRolesTab(destinationName)
	--
	-- กดแท็บ Roles โดยไม่สนใจว่ามันเป็นชนิดอะไร
	--
	-- ที่ผ่านมาผมเดาชนิดของมันผิดหลายรอบ
	-- เดาว่าเป็นปุ่มวิทยุในกลุ่มแท็บบ้าง เป็นปุ่มวิทยุตรง ๆ บ้าง
	-- รอบนี้เลิกเดา ใช้วิธีหาสิ่งที่ชื่อ Roles แล้วกดมัน ไม่ว่าจะเป็นชนิดใด
	set clicked to false
	try
		with timeout of 25 seconds
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					delay 0.3
					if not (exists window destinationName) then return false
					tell window destinationName
						repeat with a in UI elements
							if my nameOf(a) is "Roles" then
								click a
								set clicked to true
								exit repeat
							end if
							repeat with b in UI elements of a
								if my nameOf(b) is "Roles" then
									click b
									set clicked to true
									exit repeat
								end if
								repeat with c in UI elements of b
									if my nameOf(c) is "Roles" then
										click c
										set clicked to true
										exit repeat
									end if
									repeat with d in UI elements of c
										if my nameOf(d) is "Roles" then
											click d
											set clicked to true
											exit repeat
										end if
									end repeat
									if clicked then exit repeat
								end repeat
								if clicked then exit repeat
							end repeat
							if clicked then exit repeat
						end repeat
					end tell
				end tell
			end tell
		end timeout
	on error e
		logLine("กดแท็บ Roles พังกลางทาง " & e)
	end try
	if clicked then
		logLine("กดแท็บ Roles สำเร็จ")
	else
		logLine("หาแท็บชื่อ Roles ไม่เจอในสี่ชั้นแรก")
	end if
	delay 1
	return clicked
end openRolesTab


on nameOf(elementRef)
	try
		return (name of elementRef) as string
	on error
		return ""
	end try
end nameOf


on clickRolesChoice(destinationName, wantedSetting)
	--
	-- หาช่องที่มีรายการชื่อที่ต้องการอยู่ข้างใน แล้วเลือกมัน
	--
	-- เลิกอ้างอิงชนิดของช่องโดยสิ้นเชิง
	-- เพราะเดาผิดมาหลายรอบ ทั้งช่องเลือกและปุ่มเมนู
	--
	-- วิธีใหม่ ดูที่ของจริงเลยว่าใครมีรายการ 3 Stereo อยู่ข้างใน
	-- ถ้ามี แปลว่านั่นคือช่องที่ถูกต้องแน่นอน ไม่ว่ามันจะเป็นชนิดอะไร
	-- และไม่ต้องกดอะไรมั่วเพื่อลองด้วย จึงไม่มีทางไปกดโดนปุ่มอื่นผิด
	set didChoose to false
	try
		with timeout of 30 seconds
			tell application "System Events"
				tell process fcpName
					if not (exists window destinationName) then return false
					tell window destinationName
						repeat with a in UI elements
							if my chooseIfHas(a, wantedSetting) then return true
							repeat with b in UI elements of a
								if my chooseIfHas(b, wantedSetting) then return true
								repeat with c in UI elements of b
									if my chooseIfHas(c, wantedSetting) then return true
									repeat with d in UI elements of c
										if my chooseIfHas(d, wantedSetting) then return true
									end repeat
								end repeat
							end repeat
						end repeat
					end tell
				end tell
			end tell
		end timeout
	on error e
		logLine("เลือกค่าพังกลางทาง " & e)
	end try
	return didChoose
end clickRolesChoice


on chooseIfHas(elementRef, wantedSetting)
	-- ดูว่าของชิ้นนี้มีรายการที่ต้องการอยู่ข้างในไหม โดยยังไม่ต้องกดอะไร
	-- ถ้ามีจึงค่อยกดเปิดแล้วเลือก
	set itemNames to {}
	try
		tell application "System Events"
			set itemNames to name of every menu item of menu 1 of elementRef
		end tell
	on error
		return false
	end try
	if itemNames does not contain wantedSetting then return false

	my logLine("เจอช่องที่มีรายการ " & wantedSetting & " แล้ว รายการทั้งหมด " & (itemNames as string))
	try
		tell application "System Events"
			click elementRef
			delay 0.6
			click menu item wantedSetting of menu 1 of elementRef
			delay 0.8
		end tell
		my logLine("เลือก " & wantedSetting & " เรียบร้อย")
		return true
	on error e
		my logLine("กดเลือกไม่สำเร็จ " & e)
		try
			tell application "System Events" to key code 53
		end try
		return false
	end try
end chooseIfHas


-- ============================================================
-- สร้างแทร็กเสียงเอง ด้วยปุ่ม Add Audio Track
-- ------------------------------------------------------------
-- ผู้ใช้บอกชัดแล้วว่า การเลือก preset ชื่อ 3 Stereo ช่วยไม่ได้
-- ให้เปลี่ยนมาสร้างแทร็กเองตามภาพตัวอย่างที่ส่งมาแทน
--
-- ภาพนั้นบอกโครงสร้างที่ต้องได้ไว้ครบแล้ว
--   .mxf                                    ปุ่ม Add Audio Track
--   video track                             All Titles  All Video
--   audio track-1   Channels Stereo         All Dialogue  All Effects  All Music
--   audio track-2   Channels Stereo         All Dialogue  All Effects  All Music
--   audio track-3   Channels Stereo         All Dialogue  All Effects  All Music
--
-- ข้อดีของทางนี้เมื่อเทียบกับการกดช่อง Roles as
-- ปุ่มพวกนี้มีชื่อเป็นตัวหนังสือชัดเจน คือ Add Audio Track กับ Add Role
-- เราจึงหามันเจอด้วยชื่อ ไม่ต้องเดาว่ามันเป็นของชนิดไหน
-- ต่างจากช่อง Roles as ที่ไม่มีชื่อให้จับ จึงหาไม่เจอมาตลอด
-- ============================================================

on labelOf(elementRef)
	--
	-- ขอชื่อของชิ้นส่วนบนหน้าจอ
	--
	-- บางชิ้นเก็บข้อความไว้ในช่อง name เช่นปุ่ม
	-- บางชิ้นเก็บไว้ในช่อง value เช่นข้อความธรรมดา และช่องเลือกที่โชว์ค่าอยู่
	-- ถ้าดูแค่ช่องเดียวจะพลาดอีกแบบไปทั้งหมด จึงต้องดูทั้งสองช่อง
	--
	set found to ""
	try
		set found to (name of elementRef) as string
	end try
	if found is not "" and found is not "missing value" then return found
	try
		set found to (value of elementRef) as string
	end try
	if found is "missing value" then return ""
	return found
end labelOf


on matchesAny(elementRef, wantedList, mustBeExact)
	set theLabel to my labelOf(elementRef)
	if theLabel is "" then return false
	repeat with wanted in wantedList
		if mustBeExact then
			if theLabel is (wanted as string) then return true
		else
			if theLabel starts with (wanted as string) then return true
		end if
	end repeat
	return false
end matchesAny


-- ============================================================
-- หาหน้าต่างของ Share ด้วยของข้างใน ไม่ใช่ด้วยชื่อ
-- ------------------------------------------------------------
-- บันทึกจากเครื่องจริงบอกไว้สองอย่าง
--   บรรทัด 291  ใช้หน้าต่างชื่อ (ว่างเปล่า)
--   บรรทัด 506  Can't get window "MXF-50" of process "Final Cut Pro"
--
-- แปลว่าชื่อของหน้าต่างนี้ไม่แน่นอน บางจังหวะเป็น MXF-50
-- บางจังหวะกลายเป็นค่าว่าง และบางจังหวะมันเป็นแผ่นซ้อนบนหน้าต่างหลัก
--
-- การอ้างถึงมันด้วยชื่อจึงพังเป็นระยะ ๆ อย่างที่เห็นในบันทึก
-- รุ่นนี้เปลี่ยนไปหาด้วยของที่อยู่ข้างในแทน แล้วจำเป็นลำดับที่
-- ปุ่ม Next… มีเฉพาะในหน้าต่างของ Share เท่านั้น จึงใช้เป็นตัวชี้ได้ดี
-- ============================================================

on windowHasMarker(windowIndex)
	set marker to false
	try
		tell application "System Events"
			tell process fcpName
				tell window windowIndex
					repeat with a in UI elements
						if my matchesAny(a, shareMarkers, true) then
							set marker to true
							exit repeat
						end if
						repeat with b in UI elements of a
							if my matchesAny(b, shareMarkers, true) then
								set marker to true
								exit repeat
							end if
							repeat with c in UI elements of b
								if my matchesAny(c, shareMarkers, true) then
									set marker to true
									exit repeat
								end if
							end repeat
							if marker then exit repeat
						end repeat
						if marker then exit repeat
					end repeat
				end tell
			end tell
		end tell
	end try
	return marker
end windowHasMarker


on findShareWindow()
	-- คืนค่าเป็นลำดับที่ของหน้าต่าง Share หรือ 0 ถ้าไม่เจอ
	set foundIndex to 0
	try
		with timeout of 25 seconds
			tell application "System Events"
				tell process fcpName
					set howMany to count of windows
				end tell
			end tell
		end timeout
		repeat with i from 1 to howMany
			if my windowHasMarker(i) then
				set foundIndex to i
				exit repeat
			end if
		end repeat
	on error errorText
		logLine("หาหน้าต่าง Share ไม่สำเร็จ " & errorText)
	end try
	if foundIndex is 0 then
		logLine("ไม่เจอหน้าต่างของ Share เลย")
	end if
	return foundIndex
end findShareWindow


on collectAt(windowIndex, wantedList, mustBeExact)
	--
	-- เก็บอ้างอิงของทุกชิ้นที่ชื่อหรือค่าตรงกับที่ขอ เรียงตามลำดับที่เจอ
	--
	-- ลำดับสำคัญมาก เพราะใช้ลำดับเป็นตัวบอกว่าปุ่มไหนของแทร็กไหน
	-- ปุ่ม Add Role ชิ้นแรกเป็นของ video track
	-- ชิ้นที่สองเป็นของ audio track-1 ไล่ลงไปเรื่อย ๆ
	--
	-- ค้นลึกห้าชั้นแล้วหยุด ไม่ใช้ entire contents เพราะเคยทำให้ค้างยาว
	--
	set found to {}
	if windowIndex is 0 then return {}
	try
		with timeout of 30 seconds
			tell application "System Events"
				tell process fcpName
					tell window windowIndex
						repeat with a in UI elements
							if my matchesAny(a, wantedList, mustBeExact) then set end of found to (contents of a)
							repeat with b in UI elements of a
								if my matchesAny(b, wantedList, mustBeExact) then set end of found to (contents of b)
								repeat with c in UI elements of b
									if my matchesAny(c, wantedList, mustBeExact) then set end of found to (contents of c)
									repeat with d in UI elements of c
										if my matchesAny(d, wantedList, mustBeExact) then set end of found to (contents of d)
										repeat with f in UI elements of d
											if my matchesAny(f, wantedList, mustBeExact) then set end of found to (contents of f)
											repeat with g in UI elements of f
												if my matchesAny(g, wantedList, mustBeExact) then set end of found to (contents of g)
											end repeat
										end repeat
									end repeat
								end repeat
							end repeat
						end repeat
					end tell
				end tell
			end tell
		end timeout
	on error errorText
		logLine("ค้นหาชิ้นส่วนพังกลางทาง " & errorText)
	end try
	return found
end collectAt


on countAudioTracksAt(windowIndex)
	return count of my collectAt(windowIndex, {"audio track"}, false)
end countAudioTracksAt


on clickFirstAt(windowIndex, wantedText)
	-- กดชิ้นแรกที่ชื่อตรงกับที่ขอ
	set candidates to my collectAt(windowIndex, {wantedText}, true)
	if (count of candidates) is 0 then
		logLine("ไม่เจอปุ่มชื่อ " & wantedText)
		return false
	end if
	try
		with timeout of uiTimeout seconds
			tell application "System Events" to click (item 1 of candidates)
		end timeout
		delay 0.8
		return true
	on error errorText
		logLine("กดปุ่ม " & wantedText & " ไม่สำเร็จ " & errorText)
		return false
	end try
end clickFirstAt


on openMenuAndPick(elementRef, itemName)
	--
	-- กดเปิดเมนูก่อน แล้วค่อยอ่านรายการข้างใน
	--
	-- รุ่นก่อนอ่านรายการก่อนโดยยังไม่กด บันทึกบรรทัด 505 ตอบชัดแล้วว่าไม่ได้
	--   ชิ้นนี้ไม่มีเมนูให้เปิด
	-- แปลว่าปุ่มแบบนี้ยังไม่สร้างเมนูขึ้นมาจนกว่าจะถูกกด
	-- จึงต้องกลับลำดับ กดก่อน อ่านทีหลัง
	--
	-- ถ้าอ่านแล้วไม่มีรายการที่ต้องการ จะกด Escape ปิดเมนูทิ้งทันที
	-- จะได้ไม่มีเมนูค้างเปิดไปขวางขั้นตอนถัดไป
	--
	try
		with timeout of uiTimeout seconds
			tell application "System Events" to click elementRef
		end timeout
	on error errorText
		logLine("กดเปิดเมนูไม่สำเร็จ " & errorText)
		return false
	end try
	delay 0.8

	set itemNames to {}
	try
		with timeout of uiTimeout seconds
			tell application "System Events"
				set itemNames to name of every menu item of menu 1 of elementRef
			end tell
		end timeout
	end try

	if itemNames is {} then
		logLine("กดเปิดแล้วยังอ่านรายการในเมนูไม่ได้")
		my pressEscape()
		return false
	end if

	if itemNames does not contain itemName then
		logLine("ในเมนูไม่มี " & itemName & " มีแต่ " & (itemNames as string))
		my pressEscape()
		return false
	end if

	try
		with timeout of uiTimeout seconds
			tell application "System Events" to click menu item itemName of menu 1 of elementRef
		end timeout
		delay 0.7
		logLine("ใส่ " & itemName & " แล้ว")
		return true
	on error errorText
		logLine("เลือก " & itemName & " ไม่สำเร็จ " & errorText)
		my pressEscape()
		return false
	end try
end openMenuAndPick


on pressEscape()
	try
		with timeout of 5 seconds
			tell application "System Events" to key code 53
		end timeout
	end try
	delay 0.3
end pressEscape


on addRolesToTrack(trackNumber)
	--
	-- ใส่ Role สามอย่างให้แทร็กเสียงหนึ่งแทร็ก
	--
	-- ตำแหน่งของปุ่ม Add Role นับรวม video track ที่อยู่บนสุดด้วย
	-- ปุ่มของ audio track ที่หนึ่ง จึงเป็นปุ่มชิ้นที่สอง
	--
	-- ต้องค้นหาปุ่มใหม่ทุกครั้งก่อนกด เพราะกดหนึ่งครั้งหน้าต่างถูกสร้างใหม่
	-- ของที่จำไว้จากรอบก่อนจะใช้ไม่ได้อีกแล้ว
	--
	set wantedRoles to {"All Dialogue", "All Effects", "All Music"}
	set position to trackNumber + 1
	set addedCount to 0

	repeat with roleName in wantedRoles
		set windowIndex to my findShareWindow()
		if windowIndex is 0 then
			logLine("หน้าต่างหายไประหว่างใส่ Role ให้แทร็กที่ " & trackNumber)
			return addedCount
		end if
		set addButtons to my collectAt(windowIndex, {"Add Role"}, true)
		if (count of addButtons) < position then
			logLine("ไม่เจอปุ่ม Add Role ชิ้นที่ " & position & " มีอยู่ " & (count of addButtons) & " ชิ้น")
			return addedCount
		end if
		if my openMenuAndPick(item position of addButtons, roleName as string) then
			set addedCount to addedCount + 1
		end if
	end repeat
	return addedCount
end addRolesToTrack


on ensureChannelsStereo(trackNumber)
	--
	-- ดูว่าช่อง Channels ของแทร็กนี้เป็น Stereo แล้วหรือยัง
	--
	-- หาช่องนี้จากค่าที่มันโชว์อยู่ ไม่ใช่จากชื่อ
	-- เพราะในภาพ คำว่า Channels เป็นข้อความข้าง ๆ ไม่ใช่ชื่อของตัวช่อง
	-- และรุ่นก่อนหาด้วยการอ่านเมนูก็ไม่สำเร็จ เพราะเมนูยังไม่ถูกสร้าง
	--
	set windowIndex to my findShareWindow()
	if windowIndex is 0 then return false

	set boxes to my collectAt(windowIndex, {"Stereo", "Mono", "Surround"}, true)
	if (count of boxes) < trackNumber then
		logLine("ไม่เจอช่อง Channels ของแทร็กที่ " & trackNumber & " เจออยู่ " & (count of boxes) & " ช่อง")
		return false
	end if

	set theBox to item trackNumber of boxes
	if my labelOf(theBox) is "Stereo" then
		logLine("Channels ของแทร็กที่ " & trackNumber & " เป็น Stereo อยู่แล้ว")
		return true
	end if
	return my openMenuAndPick(theBox, "Stereo")
end ensureChannelsStereo


on openRolesTabAt(windowIndex)
	-- กดแท็บ Roles ในหน้าต่างที่ระบุ
	set clicked to false
	set tabs to my collectAt(windowIndex, {"Roles"}, true)
	if (count of tabs) is 0 then
		logLine("ไม่เจอแท็บชื่อ Roles ในหน้าต่างนี้")
		return false
	end if
	try
		with timeout of uiTimeout seconds
			tell application "System Events" to click (item 1 of tabs)
		end timeout
		set clicked to true
	on error errorText
		logLine("กดแท็บ Roles ไม่สำเร็จ " & errorText)
	end try
	delay 1
	return clicked
end openRolesTabAt


on buildRolesLayout(destinationName)
	--
	-- สร้างแทร็กเสียงสามแทร็กตามภาพตัวอย่างที่ผู้ใช้ส่งมา
	--
	-- ทุกขั้นตอนหาหน้าต่างใหม่ก่อนเสมอ ไม่จำลำดับที่ไว้ข้ามขั้น
	-- เพราะบันทึกจริงแสดงให้เห็นว่าหน้าต่างนี้เปลี่ยนชื่อและเปลี่ยนตำแหน่งได้
	--
	set windowIndex to 0
	repeat with waited from 1 to 15
		set windowIndex to my findShareWindow()
		if windowIndex is not 0 then exit repeat
		delay 1
	end repeat
	if windowIndex is 0 then
		logLine("ไม่เจอหน้าต่างของ " & destinationName & " จึงสร้างแทร็กเสียงไม่ได้")
		return false
	end if
	logLine("เจอหน้าต่างของ Share เป็นหน้าต่างที่ " & windowIndex)

	if not my openRolesTabAt(windowIndex) then
		dumpWindowTree(destinationName)
		return false
	end if

	set windowIndex to my findShareWindow()
	set trackCount to my countAudioTracksAt(windowIndex)
	logLine("ตอนนี้มีแทร็กเสียงอยู่ " & trackCount & " แทร็ก")

	if trackCount ≥ 3 then
		say("มีแทร็กเสียงครบสามแทร็กแล้ว")
		return true
	end if

	repeat with trackNumber from (trackCount + 1) to 3
		set windowIndex to my findShareWindow()
		if windowIndex is 0 then
			logLine("หน้าต่างหายไปก่อนจะเพิ่มแทร็กที่ " & trackNumber)
			return false
		end if
		if not my clickFirstAt(windowIndex, "Add Audio Track") then
			logLine("กดปุ่ม Add Audio Track ไม่ได้ หยุดการสร้างแทร็ก")
			dumpWindowTree(destinationName)
			return false
		end if
		logLine("เพิ่มแทร็กเสียงที่ " & trackNumber & " แล้ว")
		my ensureChannelsStereo(trackNumber)
		set addedCount to my addRolesToTrack(trackNumber)
		logLine("แทร็กที่ " & trackNumber & " ใส่ Role ได้ " & addedCount & " จาก 3")
	end repeat

	set windowIndex to my findShareWindow()
	set finalCount to my countAudioTracksAt(windowIndex)
	logLine("สร้างเสร็จแล้ว มีแทร็กเสียง " & finalCount & " แทร็ก")
	if finalCount ≥ 3 then
		say("ตั้งแทร็กเสียงครบสามแทร็กแล้ว")
		return true
	end if
	dumpWindowTree(destinationName)
	return false
end buildRolesLayout



on setRolesTo(destinationName, wantedSetting)
	--
	-- ตั้งค่าช่อง Roles as ให้เป็นค่าที่ห้องข่าวต้องการ
	--
	-- ความผิดพลาดร้ายแรงของรุ่นก่อน
	-- ตอนตั้งค่าอัตโนมัติไม่สำเร็จ โปรแกรมเปิดหน้าต่างเตือนขึ้นมาบอกให้ผู้ใช้ตั้งเอง
	-- แต่หน้าต่างเตือนนั้นบล็อกทุกอย่างไว้ ผู้ใช้จึงกดอะไรไม่ได้เลย
	-- กลายเป็นบอกให้ทำ แล้วตัวเองขวางไม่ให้ทำ
	--
	-- รุ่นนี้จึงไม่เปิดหน้าต่างเตือนขวางไว้อีก
	-- ใช้การแจ้งเตือนแบบไม่ขวาง แล้วเฝ้าดูค่าไปเรื่อย ๆ
	-- พอผู้ใช้ตั้งเองเสร็จ โปรแกรมจะรู้เองแล้วไปต่อทันที

	-- ต้องรอหน้าต่างโผล่ก่อนเสมอ ห้ามรีบเข้าไปอ่าน
	if not waitForWindowNamed(destinationName, 15) then
		logLine("ไม่เจอหน้าต่าง " & destinationName & " จึงตั้ง Roles ไม่ได้")
	end if
	openRolesTab(destinationName)
	set beforeValue to findRolesPopupValue(destinationName)
	logLine("Roles as ตอนนี้คือ [" & beforeValue & "]")
	if beforeValue is "" then
		-- อ่านค่าไม่ได้ แปลว่ายังหาช่องไม่เจอ จดผังไว้ทันทีเพื่อหาสาเหตุ
		dumpWindowTree(destinationName)
	end if

	if beforeValue is wantedSetting then
		say("Roles เป็น " & wantedSetting & " อยู่แล้ว")
		return true
	end if

	if clickRolesChoice(destinationName, wantedSetting) then
		set afterValue to findRolesPopupValue(destinationName)
		logLine("Roles as หลังตั้งคือ [" & afterValue & "]")
		if afterValue is wantedSetting then
			say("ตั้ง Roles เป็น " & wantedSetting & " แล้ว")
			return true
		end if
	end if

	-- ตั้งเองไม่สำเร็จ จดโครงสร้างไว้ก่อน แล้วขอให้ผู้ใช้ช่วย โดยไม่ขวางการกดใด ๆ
	logLine("ตั้งค่าอัตโนมัติไม่สำเร็จ เปลี่ยนเป็นรอให้ผู้ใช้ตั้งเอง")
	dumpWindowTree(destinationName)
	say("กรุณาตั้ง Roles as เป็น " & wantedSetting & " ในหน้าต่าง " & destinationName)

	-- ยกหน้าต่างของ Final Cut Pro ขึ้นมาให้ผู้ใช้กดได้สะดวก
	try
		tell application "Final Cut Pro" to activate
	end try

	repeat with i from 1 to 90
		delay 2
		set nowValue to findRolesPopupValue(destinationName)
		if nowValue is wantedSetting then
			logLine("ผู้ใช้ตั้งค่าเองเรียบร้อยแล้ว")
			say("ตั้ง Roles เรียบร้อย ทำงานต่อ")
			return true
		end if
		if nowValue is "" then
			-- หน้าต่างหายไปแล้ว แปลว่าผู้ใช้กดต่อไปเองหรือปิดไปแล้ว
			logLine("ไม่พบหน้าต่างแล้ว ถือว่าผู้ใช้จัดการต่อเอง")
			return false
		end if
		if i mod 10 is 0 then
			say("ยังรอให้ตั้ง Roles as เป็น " & wantedSetting & " อยู่")
		end if
	end repeat

	logLine("รอครบเวลาแล้วยังไม่ได้ตั้ง")
	return false
end setRolesTo


on shareTo(destinationName, humanName, rolesSetting)
	--
	-- สั่งเอ็กพอร์ตหนึ่งแบบ
	--
	-- กฎเหล็กของรุ่นนี้
	-- ห้ามเปิดหน้าต่างที่บล็อกทุกอย่าง ในจังหวะที่ผู้ใช้ต้องไปกดใน Final Cut Pro
	-- รุ่นก่อนทำแบบนั้น กลายเป็นบอกให้ผู้ใช้ไปตั้งค่า แล้วตัวเองขวางไม่ให้ตั้ง
	-- ถ้าต้องให้ผู้ใช้ช่วย ให้ใช้การแจ้งเตือนแบบไม่ขวาง แล้วเฝ้าดูเอง

	say("กำลังสั่งสร้าง " & humanName)

	repeat with attemptNumber from 1 to 3
		set opened to false
		try
			with timeout of uiTimeout seconds
				tell application "System Events"
					tell process fcpName
						set frontmost to true
						delay 0.3
						set fileMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "File")
						set shareItem to (first menu item of fileMenu whose name starts with "Share")
						click (first menu item of menu 1 of shareItem whose name starts with destinationName)
						set opened to true
					end tell
				end tell
			end timeout
		on error e
			logLine("เปิดเมนู Share ไม่สำเร็จ " & e)
		end try

		if not opened then
			say("เปิดหน้าต่าง " & humanName & " ไม่สำเร็จ")
			return false
		end if

		-- รอหน้าต่างของปลายทางโผล่ก่อน
		--
		-- เดิมรอด้วยชื่อหน้าต่าง แล้วบันทึกจริงขึ้นว่า
		--   รอหน้าต่าง MXF-50 ไม่เจอ หน้าต่างที่มีคือ Final Cut Pro
		-- ซ้ำ ๆ ทุกรอบ แปลว่าหน้าต่างนี้ไม่ได้ชื่อตามปลายทางเสมอไป
		-- บางครั้งเป็นแผ่นซ้อนบนหน้าต่างหลัก บางครั้งชื่อเป็นค่าว่าง
		--
		-- จึงเปลี่ยนมารอด้วยของที่อยู่ข้างในหน้าต่างแทน ซึ่งไม่เปลี่ยนไปมา
		repeat with waited from 1 to 15
			if my findShareWindow() is not 0 then exit repeat
			delay 1
		end repeat

		-- ตั้งค่าเสียงให้ถูกก่อน ถ้าปลายทางนี้ต้องใช้
		--
		-- ลำดับนี้มีเหตุผล
		-- ผู้ใช้บอกแล้วว่าการเลือก preset ชื่อ 3 Stereo ช่วยไม่ได้
		-- จึงสร้างแทร็กเองด้วยปุ่ม Add Audio Track เป็นทางหลัก
		-- ปุ่มพวกนั้นมีชื่อเป็นตัวหนังสือ เราจึงหาเจอ ต่างจากช่อง Roles as
		--
		-- ถ้าสร้างเองไม่สำเร็จ ค่อยถอยไปใช้วิธีเลือก preset เป็นทางสำรอง
		if rolesSetting is not "" then
			if not buildRolesLayout(destinationName) then
				logLine("สร้างแทร็กเองไม่สำเร็จ ลองวิธีเลือก preset เป็นทางสำรอง")
				setRolesTo(destinationName, rolesSetting)
			end if
		end if

		if pressButtons({"Next…", "Next...", "Next"}) then logLine("กดปุ่ม Next แล้ว")
		delay 2

		-- ตรวจว่าเลือกงานครบหรือไม่
		-- ถ้าครบ หน้าต่างจะถามหาแค่โฟลเดอร์ ไม่มีช่องกรอกชื่อไฟล์
		set fieldCount to countPanelFields()
		logLine("รอบที่ " & attemptNumber & " หน้าต่างเซฟมีช่องกรอก " & fieldCount & " ช่อง")

		if fieldCount is 0 then
			-- เลือกครบแล้ว เซฟได้เลย
			if pressButtons({"Save", "Choose", "Open", "Export"}) then
				logLine("กดยืนยันหน้าต่างเซฟแล้ว")
			else
				try
					with timeout of uiTimeout seconds
						tell application "System Events" to tell process fcpName to key code 36
					end timeout
					logLine("ใช้ปุ่ม Return แทน")
				end try
			end if
			delay 1.5
			pressButtons({"Replace", "แทนที่"})
			say("สั่ง " & humanName & " เรียบร้อย")
			return true
		end if

		-- มีช่องกรอกชื่อไฟล์ แปลว่า Final Cut Pro เห็นงานที่เลือกอยู่แค่ชิ้นเดียว
		-- ถ้าปล่อยไปจะได้ไฟล์มาก้อนเดียว ซึ่งคือปัญหาที่เจอมาตลอด
		-- ยกเลิกก่อน แล้วซ่อมการเลือกด้วยตัวเอง ไม่รบกวนผู้ใช้
		logLine("เลือกงานไม่ครบ ยกเลิกแล้วซ่อมการเลือกเอง")
		pressButtons({"Cancel", "ยกเลิก"})
		delay 1
		pressButtons({"Cancel", "ยกเลิก"})
		delay 1

		if attemptNumber is 3 then exit repeat

		say("เลือกงานย่อยไม่ครบ กำลังเลือกใหม่ให้เอง")
		selectAllProjects()
		delay 1
		say("กำลังลองสั่ง " & humanName & " อีกครั้ง")
	end repeat

	logLine("ลองครบ 3 รอบแล้วยังเลือกไม่ครบ")
	say("ยังเลือกงานไม่ครบ ข้าม " & humanName & " ไปก่อน")
	return false
end shareTo


-- ============================================================
-- เฝ้าดูและเก็บไฟล์มาไว้ที่ถูกต้อง
-- ============================================================

on monitorAndCollect(outFolder, namesFile, totalFiles)
	set finished to false
	set lastDone to -1
	set quietRounds to 0
	set roundNumber to 0

	repeat
		set roundNumber to roundNumber + 1

		-- ตามเก็บไฟล์ที่เขียนเสร็จแล้ว มาไว้ในโฟลเดอร์ปลายทาง
		try
			do shell script "/usr/bin/env python3 " & ¬
				quoted form of (resourcesPath & "/tools/collect_outputs.py") & ¬
				" " & quoted form of outFolder & " " & quoted form of namesFile & ¬
				" --settle 2"
		end try

		set doneCount to 0
		try
			set doneCount to (do shell script "/usr/bin/env python3 " & ¬
				quoted form of (resourcesPath & "/tools/watch_outputs.py") & ¬
				" " & quoted form of outFolder & " " & quoted form of namesFile & ¬
				" --settle 0.5 | head -1") as integer
		end try

		if doneCount ≥ totalFiles then
			set finished to true
			exit repeat
		end if

		set percent to 0
		if totalFiles > 0 then set percent to round (doneCount * 100 / totalFiles)

		if doneCount > lastDone then
			set quietRounds to 0
			set lastDone to doneCount
			say("เก็บไฟล์แล้ว " & doneCount & " จาก " & totalFiles)
		else
			set quietRounds to quietRounds + 1
		end if

		-- บอกให้รู้ว่ายังทำงานอยู่ ไม่ได้ค้าง
		set heartbeat to "กำลังตรวจรอบที่ " & roundNumber
		if quietRounds > 0 then
			set heartbeat to heartbeat & "   ไม่มีไฟล์ใหม่มา " & quietRounds & " รอบ"
		end if

		set message to "กำลังเอ็กพอร์ตและเก็บไฟล์" & return & return & ¬
			bar(percent) & "  " & percent & "%" & return & return & ¬
			"ได้แล้ว " & doneCount & " จาก " & totalFiles & " ไฟล์" & return & ¬
			heartbeat & return & return & ¬
			"เก็บไว้ที่" & return & outFolder
		if quietRounds > 25 then
			set message to message & return & return & ¬
				"เงียบมาสักพักแล้ว ถ้า Final Cut Pro ทำเสร็จหมดแล้ว" & return & ¬
				"กดปุ่ม หยุดรอ ได้เลย"
		end if

		-- ยกหน้าต่างขึ้นหน้าเฉพาะรอบแรก
		-- ถ้ายกทุกรอบ จะแย่งโฟกัสจากผู้ใช้ตลอดเวลา ทำอย่างอื่นไม่ได้เลย
		if roundNumber is 1 then activate
		set reply to display dialog message ¬
			buttons {"หยุดรอ", "เปิดโฟลเดอร์"} default button "หยุดรอ" ¬
			giving up after 4 with title appTitle
		if gave up of reply is false then
			if button returned of reply is "เปิดโฟลเดอร์" then
				do shell script "open " & quoted form of outFolder
			else
				exit repeat
			end if
		end if
	end repeat

	if finished then
		say("ครบทุกไฟล์แล้ว " & totalFiles & " ไฟล์")
		set headline to "เสร็จเรียบร้อย ได้ไฟล์ครบ " & totalFiles & " ไฟล์"
	else
		-- บอกตรง ๆ ว่าขาดไฟล์ไหนบ้าง
		-- ดีกว่าให้ผู้ใช้ไปนั่งไล่เทียบรายชื่อเองทีละบรรทัด
		set missingList to ""
		try
			set missingList to do shell script "/usr/bin/env python3 " & ¬
				quoted form of (resourcesPath & "/tools/watch_outputs.py") & ¬
				" " & quoted form of outFolder & " " & quoted form of namesFile & ¬
				" --settle 0.5 --missing | head -20"
		end try
		say("หยุดรอ ยังขาดไฟล์อยู่")
		logLine("ไฟล์ที่ยังขาด" & return & missingList)
		set headline to "หยุดรอแล้ว ยังได้ไม่ครบ" & return & return & ¬
			"ไฟล์ที่ยังขาด" & return & missingList & return & return & ¬
			"ใช้ปุ่ม เมนูอื่น แล้ว แก้ปัญหา แล้ว เก็บไฟล์ที่ตกค้าง"
	end if

	activate
		set answer to button returned of (display dialog ¬
		headline & return & return & "ไฟล์อยู่ที่" & return & outFolder ¬
		buttons {"ปิด", "เปิดโฟลเดอร์"} default button "เปิดโฟลเดอร์" with title appTitle)
	if answer is "เปิดโฟลเดอร์" then do shell script "open " & quoted form of outFolder
end monitorAndCollect


on bar(percent)
	set filled to round (percent / 5)
	if filled < 0 then set filled to 0
	if filled > 20 then set filled to 20
	set output to ""
	repeat with i from 1 to 20
		if i ≤ filled then
			set output to output & "█"
		else
			set output to output & "░"
		end if
	end repeat
	return output
end bar


-- ============================================================
-- ตัวช่วยคุยกับ Final Cut Pro ทุกตัวมีเวลาจำกัดเสมอ
-- ============================================================

on menuState(menuName, itemPrefix)
	try
		with timeout of uiTimeout seconds
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					delay 0.3
					set target to (first menu item of menu 1 of (first menu bar item of menu bar 1 whose name is menuName) whose name starts with itemPrefix)
					if enabled of target then return "enabled"
					return "disabled"
				end tell
			end tell
		end timeout
	on error
		return "missing"
	end try
end menuState


on clickMenu(menuName, itemPrefix)
	try
		with timeout of uiTimeout seconds
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					delay 0.4
					click (first menu item of menu 1 of (first menu bar item of menu bar 1 whose name is menuName) whose name starts with itemPrefix)
				end tell
			end tell
		end timeout
	on error e
		logLine("กดเมนู " & itemPrefix & " ไม่สำเร็จ " & e)
	end try
end clickMenu


-- ============================================================
-- การเลือกงานย่อยให้ครบทุกก้อน
-- ------------------------------------------------------------
-- นี่คือหัวใจของการเอ็กพอร์ตต่อเนื่องทีเดียวทุกก้อน
--
-- Final Cut Pro เอ็กพอร์ตพร้อมกันได้อยู่แล้ว ถ้าเลือกงานไว้ครบ
-- สั่ง Share หนึ่งครั้ง มันจะเข้าคิวให้ทุกก้อนแล้วทยอยทำเอง
-- ปัญหาที่ได้ไฟล์เดียวจึงไม่ได้อยู่ที่การสั่ง แต่อยู่ที่การเลือก
--
-- บทเรียนจากรอบก่อน
-- เคยสั่งเลือกทั้งหมดขณะที่โฟกัสอยู่ในไทม์ไลน์
-- คำสั่งนั้นจึงไปเลือกคลิปทั้งหมดในงานเดียว ไม่ใช่เลือกงานทั้งหมด
-- ผลคือได้ไฟล์มาก้อนเดียว
--
-- รุ่นนี้จึงย้ายโฟกัสไปที่ Browser ให้แน่ก่อน แล้วค่อยสั่งเลือกทั้งหมด
-- และใช้เมนูจริงเสมอ ไม่ใช้ปุ่มลัด เพราะปุ่มลัดวิ่งผ่านผังแป้นพิมพ์
-- ซึ่งเคยทำให้ตัวอักษรเพี้ยนมาแล้ว
-- ============================================================

on goToArea(areaPrefix)
	-- ย้ายโฟกัสไปยังพื้นที่ที่ต้องการ ผ่านเมนู Window แล้ว Go To
	-- ถ้าหาไม่เจอ จะจดชื่อรายการจริงทั้งหมดไว้ในบันทึก
	-- จะได้รู้ว่าเครื่องนี้เรียกพื้นที่นั้นว่าอะไร โดยไม่ต้องเดา
	set moved to false
	try
		with timeout of uiTimeout seconds
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					delay 0.3
					set windowMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "Window")
					set goToItem to (first menu item of windowMenu whose name starts with "Go To")
					set areaNames to name of every menu item of menu 1 of goToItem
					if (areaNames as string) does not contain areaPrefix then
						my logLine("ในเมนู Go To ไม่มี " & areaPrefix & " มีแต่ " & (areaNames as string))
					else
						click (first menu item of menu 1 of goToItem whose name starts with areaPrefix)
						set moved to true
					end if
				end tell
			end tell
		end timeout
	on error e
		logLine("ย้ายโฟกัสไป " & areaPrefix & " ไม่สำเร็จ " & e)
	end try

	if not moved then
		-- ปิดเมนูที่อาจค้างเปิดอยู่ ไม่ให้ไปขวางขั้นตอนถัดไป
		try
			with timeout of 5 seconds
				tell application "System Events" to key code 53
			end timeout
		end try
	end if
	return moved
end goToArea


on selectAllProjects()
	-- เลือกงานย่อยทุกก้อนใน Browser
	-- คืนค่า true เมื่อสั่งได้ครบทั้งสองขั้น
	set moved to goToArea("Browser")
	if not moved then
		logLine("ไปที่ Browser ไม่ได้ จะลองสั่งเลือกทั้งหมดตามเดิม")
	end if
	delay 0.5
	set chosen to (menuState("Edit", "Select All") is "enabled")
	if not chosen then
		logLine("คำสั่ง Select All กดไม่ได้ตอนนี้")
		return false
	end if
	clickMenu("Edit", "Select All")
	delay 0.8
	logLine("สั่งเลือกงานย่อยทั้งหมดใน Browser แล้ว")
	return moved
end selectAllProjects


on waitForSheet(maxSeconds)
	-- รอจนหน้าต่างเซฟโผล่ ไม่ว่ามันจะเป็นของกระบวนการไหน
	-- นับทั้งแบบแผ่นซ้อนบนหน้าต่าง และแบบหน้าต่างแยกที่ระบบสร้างให้
	repeat with i from 1 to maxSeconds
		repeat with processName in panelProcesses()
			try
				with timeout of uiTimeout seconds
					tell application "System Events"
						tell process processName
							repeat with windowRef in windows
								if (count of sheets of windowRef) > 0 then
									my logLine("เจอหน้าต่างเซฟแบบแผ่นซ้อน ใน " & processName)
									return true
								end if
								try
									if (exists button "Save" of windowRef) then
										my logLine("เจอหน้าต่างเซฟแบบหน้าต่างแยก ใน " & processName)
										return true
									end if
								end try
							end repeat
						end tell
					end tell
				end timeout
			end try
		end repeat
		delay 1
	end repeat
	logLine("รอหน้าต่างเซฟจนครบเวลาแล้วไม่เจอ")
	return false
end waitForSheet


on panelProcesses()
	--
	-- หัวใจของการแก้ปัญหาทั้งหมด
	--
	-- Final Cut Pro เป็นโปรแกรมจาก App Store ซึ่ง macOS บังคับให้อยู่ในกรอบความปลอดภัย
	-- หน้าต่างเซฟและหน้าต่างเปิดไฟล์ของโปรแกรมแบบนี้
	-- จะไม่ได้เป็นของตัวโปรแกรมเอง แต่ระบบแยกไปไว้อีกกระบวนการหนึ่งต่างหาก
	--
	-- ที่ผ่านมาโปรแกรมไปหาปุ่ม Save ในตัว Final Cut Pro จึงไม่มีวันเจอ
	-- นี่คือสาเหตุที่กดปุ่มไม่ติด พิมพ์ไม่เข้า และบังคับที่เซฟไม่ได้ ทุกครั้ง
	--
	-- ตัวนี้จึงรวบรวมชื่อกระบวนการที่อาจถือหน้าต่างเซฟอยู่ ให้ครบทุกตัว
	set names to {fcpName}
	try
		with timeout of uiTimeout seconds
			tell application "System Events"
				repeat with processRef in (every process whose name contains "openAndSavePanel")
					set end of names to (name of processRef)
				end repeat
				repeat with processRef in (every process whose name contains "OpenAndSavePanel")
					set end of names to (name of processRef)
				end repeat
			end tell
		end timeout
	end try
	return names
end panelProcesses


on pressButtons(buttonNames)
	-- กดปุ่มตัวแรกที่หาเจอ โดยกวาดทุกกระบวนการที่อาจถือหน้าต่างอยู่
	--
	-- ต้องมีเวลาจำกัดเสมอ เพราะตอน Final Cut Pro ทำงานหนัก มันตอบช้ามาก
	-- ถ้าไม่จำกัดเวลา โปรแกรมจะค้างแล้วตายด้วย AppleEvent timed out
	-- ซึ่งเป็นสาเหตุที่รอบก่อน ๆ หยุดหลังก้อนแรก
	repeat with processName in panelProcesses()
		try
			with timeout of uiTimeout seconds
				tell application "System Events"
					tell process processName
						repeat with windowRef in windows
							repeat with sheetRef in sheets of windowRef
								repeat with buttonName in buttonNames
									try
										click button buttonName of sheetRef
										my logLine("กดปุ่ม " & buttonName & " ใน " & processName & " สำเร็จ")
										return true
									end try
								end repeat
							end repeat
							repeat with buttonName in buttonNames
								try
									click button buttonName of windowRef
									my logLine("กดปุ่ม " & buttonName & " ใน " & processName & " สำเร็จ")
									return true
								end try
							end repeat
						end repeat
					end tell
				end tell
			end timeout
		end try
	end repeat
	return false
end pressButtons


-- ============================================================
-- ตัวช่วยเรียกโปรแกรมอ่านและแยกไทม์ไลน์
-- ============================================================

on runBrief(inputPath, gapSeconds)
	return do shell script "/usr/bin/env python3 " & ¬
		quoted form of (resourcesPath & "/tools/fcpxml_segments.py") & ¬
		" " & quoted form of inputPath & " --min-gap " & gapSeconds & " --brief"
end runBrief


on runSplit(inputPath, gapSeconds, outputPath, eventName)
	return do shell script "/usr/bin/env python3 " & ¬
		quoted form of (resourcesPath & "/tools/fcpxml_split.py") & ¬
		" " & quoted form of inputPath & " --min-gap " & gapSeconds & ¬
		" --event-name " & quoted form of eventName & ¬
		" -o " & quoted form of outputPath
end runSplit


on askGapSeconds(currentValue)
	try
		activate
		return text returned of (display dialog ¬
			"ปรับจำนวนก้อน" & return & return & ¬
			"ได้ก้อนน้อยเกินไป ให้ลดตัวเลขลง เช่น 0.1" & return & ¬
			"ได้ก้อนเยอะเกินไป ให้เพิ่มขึ้น เช่น 1 หรือ 2" ¬
			default answer currentValue ¬
			buttons {"ยกเลิก", "ลองใหม่"} default button "ลองใหม่" with title appTitle)
	on error
		return ""
	end try
end askGapSeconds
