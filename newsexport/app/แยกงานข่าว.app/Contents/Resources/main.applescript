-- ============================================================
-- หน้าจอหลักของโปรแกรมแยกงานข่าว
-- ------------------------------------------------------------
-- ไฟล์นี้ทำหน้าที่เป็น "หน้าตา" ของโปรแกรม
-- แสดงหน้าต่างแบบ Mac ให้ผู้ใช้กดปุ่ม โดยไม่ต้องเห็น Terminal เลย
--
-- แนวคิดสำคัญ
-- Final Cut Pro ไม่เปิดให้สั่งงานจากภายนอกโดยตรง
-- โปรแกรมจึงต้อง "กดเมนูแทนผู้ใช้" ผ่านระบบช่วยเหลือของ macOS
-- ทุกขั้นตอนจึงมีทางสำรองเสมอ ถ้ากดแทนไม่ได้ จะบอกผู้ใช้ให้กดเอง
-- ไม่มีขั้นตอนไหนที่ค้างแล้วไปต่อไม่ได้
-- ============================================================

property appTitle : "แยกงานข่าว"
property fcpName : "Final Cut Pro"

-- ตำแหน่งโฟลเดอร์ไฟล์ตัวช่วย ส่งมาจากตัวเริ่มโปรแกรม
global resourcesPath
-- โฟลเดอร์พักงานชั่วคราว
global workPath


on run argv
	if (count of argv) > 0 then
		set resourcesPath to item 1 of argv
	else
		set resourcesPath to (do shell script "dirname " & quoted form of (POSIX path of (path to me)))
	end if
	set workPath to (do shell script "mkdir -p ~/Library/Caches/fcpx-news-export && echo ~/Library/Caches/fcpx-news-export")
	showMainMenu()
end run


-- ============================================================
-- หน้าจอหลัก
-- ============================================================

on showMainMenu()
	repeat
		set choice to button returned of (display dialog ¬
			"โปรแกรมนี้จะช่วยแยกข่าวในไทม์ไลน์ออกเป็นก้อน ๆ" & return & ¬
			"แล้วช่วยเอ็กพอร์ตให้ครบทุกก้อน ทั้งไฟล์ mov และ mxf" & return & return & ¬
			"ให้เปิดงานข่าวที่ต้องการค้างไว้ใน Final Cut Pro" & return & ¬
			"แล้วกดปุ่ม เริ่มทำงาน ได้เลย" ¬
			buttons {"ปิด", "วิธีใช้", "เริ่มทำงาน"} ¬
			default button "เริ่มทำงาน" ¬
			with title appTitle)

		if choice is "ปิด" then
			return
		else if choice is "วิธีใช้" then
			showHelp()
		else
			runWorkflow()
		end if
	end repeat
end showMainMenu


on showHelp()
	display dialog ¬
		"ขั้นตอนที่โปรแกรมทำให้" & return & return & ¬
		"1. ดึงไทม์ไลน์ออกมาจาก Final Cut Pro" & return & ¬
		"2. หาว่ามีข่าวกี่ก้อน แล้วให้คุณตรวจก่อน" & return & ¬
		"3. แยกเป็นงานย่อย ตั้งชื่อลงท้าย -1 -2 -3 ให้เอง" & return & ¬
		"4. นำงานย่อยกลับเข้า Final Cut Pro" & return & ¬
		"5. ช่วยสั่งเอ็กพอร์ต mov และ mxf ให้ครบทุกก้อน" & return & return & ¬
		"สิ่งที่โปรแกรมไม่ทำ" & return & return & ¬
		"ไม่แก้งานเดิมของคุณเลย อ่านอย่างเดียว" & return & ¬
		"ไม่แปลงไฟล์เอง จึงไม่ทำให้เสียงหรือ Roles เพี้ยน" & return & ¬
		"ไม่สร้างไฟล์ใด ๆ จนกว่าคุณจะกดยืนยัน" ¬
		buttons {"เข้าใจแล้ว"} default button 1 with title appTitle
end showHelp


-- ============================================================
-- ลำดับการทำงานทั้งหมด
-- ============================================================

on runWorkflow()
	try
		-- ขั้นที่ 0 ตรวจความพร้อม
		if not ensureFinalCutRunning() then return
		if not ensureAccessibility() then return

		-- ขั้นที่ 1 ดึงไทม์ไลน์ออกมา
		set xmlPath to exportTimeline()
		if xmlPath is "" then return

		-- ขั้นที่ 2 อ่านว่ามีกี่ก้อน แล้วให้ผู้ใช้ตรวจ
		set gapSeconds to "0.2"
		repeat
			set reportText to runToolBrief(xmlPath, gapSeconds)
			set answer to button returned of (display dialog ¬
				reportText & return & ¬
				"รายการนี้ถูกต้องไหม" ¬
				buttons {"ยกเลิก", "ปรับจำนวนก้อน", "ถูกต้อง ไปต่อ"} ¬
				default button "ถูกต้อง ไปต่อ" ¬
				with title appTitle)

			if answer is "ยกเลิก" then return
			if answer is "ถูกต้อง ไปต่อ" then exit repeat

			set gapSeconds to askGapSeconds(gapSeconds)
			if gapSeconds is "" then return
		end repeat

		-- ขั้นที่ 3 แยกงานจริง
		set splitPath to (workPath & "/แยกแล้ว.fcpxml")
		runTool("fcpxml_split.py", xmlPath, gapSeconds, splitPath)

		-- ขั้นที่ 4 นำกลับเข้า Final Cut Pro
		importTimeline(splitPath)

		-- ขั้นที่ 5 ช่วยเอ็กพอร์ต
		offerExport()

	on error errorMessage number errorNumber
		if errorNumber is -128 then return -- ผู้ใช้กดยกเลิกเอง
		display dialog ¬
			"เกิดปัญหาระหว่างทำงาน" & return & return & ¬
			errorMessage & return & return & ¬
			"ถ้าไม่เข้าใจข้อความนี้ ให้ถ่ายรูปหน้าจอส่งกลับมาได้เลย" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
	end try
end runWorkflow


-- ============================================================
-- ขั้นที่ 0 ตรวจความพร้อมของเครื่อง
-- ============================================================

on ensureFinalCutRunning()
	tell application "System Events"
		set isRunning to (exists process fcpName)
	end tell
	if isRunning then return true

	set answer to button returned of (display dialog ¬
		"ยังไม่ได้เปิด Final Cut Pro" & return & return & ¬
		"ให้เปิด Final Cut Pro และเปิดงานข่าวที่ต้องการค้างไว้ก่อน" ¬
		buttons {"ยกเลิก", "เปิดให้เลย"} default button "เปิดให้เลย" with title appTitle)
	if answer is "ยกเลิก" then return false

	tell application "Final Cut Pro" to activate
	display dialog ¬
		"เปิด Final Cut Pro แล้ว" & return & return & ¬
		"ให้เปิดงานข่าวที่ต้องการ แล้วคลิกที่ชื่องานนั้นหนึ่งครั้ง" & return & ¬
		"เสร็จแล้วกดปุ่ม พร้อมแล้ว" ¬
		buttons {"พร้อมแล้ว"} default button 1 with title appTitle
	return true
end ensureFinalCutRunning


on ensureAccessibility()
	-- ทดสอบว่าโปรแกรมได้รับอนุญาตให้กดเมนูแทนผู้ใช้หรือยัง
	try
		tell application "System Events"
			tell process fcpName to get name of menu bar 1
		end tell
		return true
	on error
		set answer to button returned of (display dialog ¬
			"ต้องเปิดสิทธิ์ให้โปรแกรมกดเมนูแทนคุณก่อน" & return & return & ¬
			"ทำครั้งเดียวจบ ขั้นตอนคือ" & return & return & ¬
			"1. กดปุ่ม เปิดหน้าตั้งค่า ข้างล่างนี้" & return & ¬
			"2. หาชื่อ แยกงานข่าว ในรายการ แล้วเปิดสวิตช์ให้เป็นสีเขียว" & return & ¬
			"3. ถ้าไม่เห็นชื่อ ให้กดปุ่มบวก แล้วเลือกโปรแกรมนี้" & return & ¬
			"4. กลับมาเปิดโปรแกรมนี้ใหม่อีกครั้ง" ¬
			buttons {"ปิด", "เปิดหน้าตั้งค่า"} default button "เปิดหน้าตั้งค่า" ¬
			with title appTitle with icon caution)
		if answer is "เปิดหน้าตั้งค่า" then
			do shell script "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
		end if
		return false
	end try
end ensureAccessibility


-- ============================================================
-- ขั้นที่ 1 ดึงไทม์ไลน์ออกมาจาก Final Cut Pro
-- ============================================================

on exportTimeline()
	-- ล้างของเก่าออกก่อน จะได้รู้แน่ว่าไฟล์ที่เจอคือไฟล์ใหม่
	do shell script "rm -rf " & quoted form of (workPath & "/ดึงออกมา") & " && mkdir -p " & quoted form of (workPath & "/ดึงออกมา")
	set outFolder to workPath & "/ดึงออกมา"

	display dialog ¬
		"ขั้นที่ 1 จาก 4" & return & return & ¬
		"กำลังจะดึงไทม์ไลน์ออกมาจาก Final Cut Pro" & return & return & ¬
		"ตรวจก่อนว่าคลิกเลือก ชื่องานข่าว ที่ต้องการไว้แล้ว" & return & ¬
		"ระหว่างนี้อย่าเพิ่งแตะเมาส์หรือคีย์บอร์ด" ¬
		buttons {"เริ่มเลย"} default button 1 with title appTitle

	set didAutomate to false
	try
		clickMenuItem("File", "Export XML")
		delay 1.5
		saveSheetTo(outFolder, "ไทม์ไลน์")
		set didAutomate to true
	on error
		set didAutomate to false
	end try

	if not didAutomate then
		-- ทางสำรอง ให้ผู้ใช้ทำเอง แล้วโปรแกรมรอไฟล์
		do shell script "open " & quoted form of outFolder
		display dialog ¬
			"กดแทนให้ไม่สำเร็จ ขอให้ทำเองสองขั้นตอนนี้" & return & return & ¬
			"1. ใน Final Cut Pro ไปที่เมนู File แล้วเลือก Export XML" & return & ¬
			"2. เซฟลงในโฟลเดอร์ที่เพิ่งเปิดขึ้นมาให้" & return & return & ¬
			"เสร็จแล้วกดปุ่ม เซฟแล้ว" ¬
			buttons {"เซฟแล้ว"} default button 1 with title appTitle
	end if

	-- รอไฟล์ปรากฏ สูงสุด 60 วินาที
	set foundPath to waitForTimelineFile(outFolder, 60)
	if foundPath is "" then
		display dialog ¬
			"ยังไม่พบไฟล์ไทม์ไลน์" & return & return & ¬
			"ลองใหม่อีกครั้ง โดยตรวจว่าได้คลิกเลือกชื่องานข่าวไว้แล้ว" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
		return ""
	end if
	return foundPath
end exportTimeline


on waitForTimelineFile(folderPath, maxSeconds)
	repeat with i from 1 to maxSeconds
		try
			set found to do shell script ¬
				"find " & quoted form of folderPath & " -maxdepth 1 \\( -name '*.fcpxmld' -o -name '*.fcpxml' \\) | head -1"
			if found is not "" then
				delay 1 -- เผื่อเวลาให้เขียนไฟล์เสร็จสมบูรณ์
				return found
			end if
		end try
		delay 1
	end repeat
	return ""
end waitForTimelineFile


-- ============================================================
-- ขั้นที่ 4 นำงานย่อยกลับเข้า Final Cut Pro
-- ============================================================

on importTimeline(splitPath)
	display dialog ¬
		"ขั้นที่ 3 จาก 4" & return & return & ¬
		"แยกงานเรียบร้อยแล้ว" & return & ¬
		"กำลังจะนำงานย่อยกลับเข้า Final Cut Pro" & return & return & ¬
		"ระหว่างนี้อย่าเพิ่งแตะเมาส์หรือคีย์บอร์ด" ¬
		buttons {"ไปต่อ"} default button 1 with title appTitle

	try
		clickMenuItem("File", "Import")
		delay 0.8
		tell application "System Events"
			tell process fcpName
				click (first menu item of menu 1 of (first menu item of menu 1 of (first menu bar item of menu bar 1 whose name is "File") whose name starts with "Import") whose name starts with "XML")
			end tell
		end tell
		delay 1.5
		openSheetAt(splitPath)
	on error
		do shell script "open -R " & quoted form of splitPath
		display dialog ¬
			"กดแทนให้ไม่สำเร็จ ขอให้ทำเองสองขั้นตอนนี้" & return & return & ¬
			"1. ใน Final Cut Pro ไปที่เมนู File แล้ว Import แล้ว XML" & return & ¬
			"2. เลือกไฟล์ชื่อ แยกแล้ว.fcpxml ที่เปิดค้างไว้ให้ใน Finder" & return & return & ¬
			"เสร็จแล้วกดปุ่ม นำเข้าแล้ว" ¬
			buttons {"นำเข้าแล้ว"} default button 1 with title appTitle
	end try
end importTimeline


-- ============================================================
-- ขั้นที่ 5 ช่วยเอ็กพอร์ต
-- ============================================================

on offerExport()
	set answer to button returned of (display dialog ¬
		"ขั้นที่ 4 จาก 4" & return & return & ¬
		"งานย่อยเข้าไปอยู่ใน Final Cut Pro แล้ว" & return & ¬
		"ชื่อลงท้ายด้วย -1 -2 -3 เรียงตามลำดับให้แล้ว" & return & return & ¬
		"ขั้นตอนสุดท้าย ให้เลือกงานย่อยทั้งหมดพร้อมกัน" & return & ¬
		"คลิกอันแรก กด Shift ค้าง แล้วคลิกอันสุดท้าย" & return & return & ¬
		"เลือกเสร็จแล้วกดปุ่มข้างล่าง" ¬
		buttons {"ทำเองต่อ", "ช่วยเอ็กพอร์ตให้"} ¬
		default button "ช่วยเอ็กพอร์ตให้" with title appTitle)

	if answer is "ทำเองต่อ" then
		display dialog ¬
			"เหลืออีกสองรอบเท่านั้น" & return & return & ¬
			"รอบที่ 1  เมนู File แล้ว Share แล้ว Export File" & return & ¬
			"          จะได้ไฟล์ mov ครบทุกก้อน" & return & return & ¬
			"รอบที่ 2  เมนู File แล้ว Share แล้ว MXF-50" & return & ¬
			"          ดูแท็บ Roles ให้เป็น 3 Stereo" & return & ¬
			"          จะได้ไฟล์ mxf ครบทุกก้อน" ¬
			buttons {"เข้าใจแล้ว"} default button 1 with title appTitle
		return
	end if

	shareWith("Export File", "ไฟล์ mov")
	shareWith("MXF-50", "ไฟล์ mxf")

	display dialog ¬
		"สั่งเอ็กพอร์ตครบทั้งสองแบบแล้ว" & return & return & ¬
		"Final Cut Pro กำลังทยอยสร้างไฟล์ให้" & return & ¬
		"ดูความคืบหน้าได้ที่ไอคอนวงกลมมุมขวาบนของ Final Cut Pro" ¬
		buttons {"เสร็จสิ้น"} default button 1 with title appTitle
end offerExport


on shareWith(destinationName, humanName)
	display dialog ¬
		"กำลังจะสั่งสร้าง " & humanName & return & return & ¬
		"ระหว่างนี้อย่าเพิ่งแตะเมาส์หรือคีย์บอร์ด" ¬
		buttons {"เริ่มเลย"} default button 1 with title appTitle
	try
		tell application "System Events"
			tell process fcpName
				set frontmost to true
				delay 0.3
				click (first menu item of menu 1 of (first menu item of menu 1 of (first menu bar item of menu bar 1 whose name is "File") whose name starts with "Share") whose name starts with destinationName)
			end tell
		end tell
		delay 2
		display dialog ¬
			"หน้าต่างตั้งค่าของ " & humanName & " เปิดขึ้นมาแล้ว" & return & return & ¬
			"ตรวจค่าให้ถูก แล้วกดปุ่ม Next และเลือกโฟลเดอร์ที่จะเก็บไฟล์" & return & return & ¬
			"เสร็จแล้วกดปุ่มข้างล่างเพื่อไปขั้นถัดไป" ¬
			buttons {"เรียบร้อย"} default button 1 with title appTitle
	on error
		display dialog ¬
			"กดแทนให้ไม่สำเร็จ ขอให้ทำเองครับ" & return & return & ¬
			"เมนู File แล้ว Share แล้วเลือก " & destinationName ¬
			buttons {"เรียบร้อย"} default button 1 with title appTitle
	end try
end shareWith


-- ============================================================
-- ตัวช่วยกดเมนูและหน้าต่างเซฟ
-- ============================================================

on clickMenuItem(menuName, itemPrefix)
	tell application "System Events"
		tell process fcpName
			set frontmost to true
			delay 0.4
			click (first menu item of menu 1 of (first menu bar item of menu bar 1 whose name is menuName) whose name starts with itemPrefix)
		end tell
	end tell
end clickMenuItem


on saveSheetTo(folderPath, fileName)
	-- ใส่ชื่อไฟล์และโฟลเดอร์ปลายทางลงในหน้าต่างเซฟ แล้วกด Save
	tell application "System Events"
		tell process fcpName
			set frontmost to true
			-- ไปยังโฟลเดอร์ที่ต้องการ ด้วยคำสั่งไปที่โฟลเดอร์ของ macOS
			keystroke "g" using {command down, shift down}
			delay 0.8
			keystroke folderPath
			delay 0.5
			key code 36
			delay 1
			-- ตั้งชื่อไฟล์
			keystroke "a" using {command down}
			delay 0.2
			keystroke fileName
			delay 0.4
			key code 36
		end tell
	end tell
end saveSheetTo


on openSheetAt(filePath)
	-- ใส่ที่อยู่ไฟล์ลงในหน้าต่างเปิดไฟล์ แล้วกด Enter
	tell application "System Events"
		tell process fcpName
			set frontmost to true
			keystroke "g" using {command down, shift down}
			delay 0.8
			keystroke filePath
			delay 0.5
			key code 36
			delay 1.2
			key code 36
		end tell
	end tell
end openSheetAt


-- ============================================================
-- ตัวช่วยเรียกโปรแกรมอ่านและแยกไทม์ไลน์
-- ============================================================

on runToolBrief(inputPath, gapSeconds)
	return do shell script "/usr/bin/env python3 " & ¬
		quoted form of (resourcesPath & "/tools/fcpxml_segments.py") & ¬
		" " & quoted form of inputPath & " --min-gap " & gapSeconds & " --brief"
end runToolBrief


on runTool(toolName, inputPath, gapSeconds, outputPath)
	set theCommand to "/usr/bin/env python3 " & quoted form of (resourcesPath & "/tools/" & toolName) & ¬
		" " & quoted form of inputPath & " --min-gap " & gapSeconds
	if outputPath is not "" then
		set theCommand to theCommand & " -o " & quoted form of outputPath
	end if
	return do shell script theCommand
end runTool


on askGapSeconds(currentValue)
	try
		set answer to text returned of (display dialog ¬
			"ปรับจำนวนก้อน" & return & return & ¬
			"ถ้าได้ก้อนน้อยเกินไป ให้ลดตัวเลขลง เช่น 0.1" & return & ¬
			"ถ้าได้ก้อนเยอะเกินไป ให้เพิ่มตัวเลขขึ้น เช่น 1 หรือ 2" & return & return & ¬
			"ตัวเลขนี้คือ ช่องว่างกี่วินาทีจึงนับว่าคั่นข่าวคนละเรื่อง" ¬
			default answer currentValue ¬
			buttons {"ยกเลิก", "ลองใหม่"} default button "ลองใหม่" with title appTitle)
		return answer
	on error
		return ""
	end try
end askGapSeconds
