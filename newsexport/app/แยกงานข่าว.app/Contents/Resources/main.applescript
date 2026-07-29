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

global resourcesPath
global workPath
global prefsPath
global logPath
global statusPath


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
	set menuItems to {¬
		"ตั้งค่า Roles  เปิดหน้าต่าง MXF-50 ให้คุณตั้ง 3 Stereo ครั้งเดียว", ¬
		"ดูค่าที่ตั้งไว้  อ่านค่า Roles ที่เครื่องนี้บันทึกไว้ในไฟล์", ¬
		"จำค่านี้ไว้  ถ่ายสำเนาค่าที่ตั้งถูกแล้ว เก็บไว้ใช้ทีหลัง", ¬
		"ใส่ค่าที่จำไว้กลับ  ใช้เมื่อค่า Roles เปลี่ยนไปเอง", ¬
		"แก้ปัญหา  ดูบันทึก และเก็บไฟล์ที่ตกค้าง"}

	repeat
		activate
		set picked to (choose from list menuItems ¬
			with title appTitle ¬
			with prompt ("เมนูเพิ่มเติม" & return & "เลือกหนึ่งข้อแล้วกดตกลง") ¬
			OK button name "ตกลง" cancel button name "กลับ" ¬
			without multiple selections allowed and empty selection allowed)
		if picked is false then return

		set choice to item 1 of picked
		if choice starts with "ตั้งค่า Roles" then
			primeRolesSetting()
		else if choice starts with "ดูค่าที่ตั้งไว้" then
			reportRolesSettings()
		else if choice starts with "จำค่านี้ไว้" then
			rememberRolesSettings()
		else if choice starts with "ใส่ค่าที่จำไว้กลับ" then
			restoreRolesSettings()
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


on showLog()
	try
		do shell script "open -R " & quoted form of logPath
		activate
		activate
	display dialog ¬
			"เปิด Finder ให้แล้ว ไฟล์ชื่อ บันทึกการทำงาน.txt" & return & return & ¬
			"ส่งไฟล์นี้กลับมาให้ผมได้เลย" ¬
			buttons {"ปิด"} default button 1 with title appTitle
	on error
		activate
		display dialog "ยังไม่มีบันทึก ลองกดปุ่ม เอ็กพอร์ต ก่อนหนึ่งครั้ง" ¬
			buttons {"ปิด"} default button 1 with title appTitle
	end try
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

	try
		do shell script "open -R " & quoted form of reportPath
	end try
	activate
	display dialog summary & return & return & ¬
		"เปิด Finder ให้แล้ว ไฟล์ชื่อ ค่า Roles ในเครื่อง.txt" ¬
		buttons {"ตกลง"} default button "ตกลง" with title appTitle
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

	if menuState("File", "Share") is "disabled" then
		activate
		display dialog ¬
			"เมนู Share กดไม่ได้" & return & return & ¬
			"ให้คลิกเลือกงานในหน้าต่าง Browser ไว้หนึ่งชิ้นก่อน" & return & ¬
			"แล้วลองใหม่อีกครั้ง" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
		return
	end if

	set opened to false
	try
		with timeout of uiTimeout seconds
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					delay 0.3
					set fileMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "File")
					set shareItem to (first menu item of fileMenu whose name starts with "Share")
					click (first menu item of menu 1 of shareItem whose name starts with "MXF-50")
					set opened to true
				end tell
			end tell
		end timeout
	on error e
		logLine("เปิดหน้าต่าง MXF-50 ไม่สำเร็จ " & e)
	end try

	if not opened then
		activate
		display dialog "เปิดหน้าต่าง MXF-50 ไม่สำเร็จ" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
		return
	end if

	waitForWindowNamed("MXF-50", 15)
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
		-- ผลทดสอบบนเครื่องจริงบอกว่าหน้าต่างชื่อตรงกับปลายทาง เช่น MXF-50
		-- แต่ใช้เวลาโผล่ ถ้ารีบทำงานต่อจะเจอแต่หน้าต่างเปล่า
		waitForWindowNamed(destinationName, 15)

		-- ตั้งค่า Roles ให้ถูกก่อน ถ้าปลายทางนี้ต้องใช้
		if rolesSetting is not "" then setRolesTo(destinationName, rolesSetting)

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

		-- เลือกไม่ครบ ยกเลิกแล้วขอให้ผู้ใช้เลือกใหม่ โดยไม่ขวางการกด
		logLine("เลือกงานไม่ครบ ยกเลิกแล้วรอให้ผู้ใช้เลือก")
		pressButtons({"Cancel", "ยกเลิก"})
		delay 1
		pressButtons({"Cancel", "ยกเลิก"})
		delay 1

		if attemptNumber is 3 then exit repeat

		say("เลือกงานย่อยไม่ครบ กรุณาเลือกให้ครบใน Final Cut Pro")
		try
			tell application "Final Cut Pro" to activate
		end try

		-- ให้เวลาผู้ใช้เลือก โดยไม่มีหน้าต่างอะไรขวางเลย
		repeat with waited from 1 to 6
			delay 5
			if waited is 3 then
				say("ยังรออยู่ เลือกอันแรก กด Shift ค้าง แล้วคลิกอันสุดท้าย")
			end if
		end repeat
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
		say("ผู้ใช้กดหยุดรอ")
		set headline to "หยุดรอแล้ว" & return & ¬
			"ถ้ายังไม่ครบ ใช้ปุ่ม เมนูอื่น แล้ว เก็บไฟล์ที่ตกค้าง"
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
