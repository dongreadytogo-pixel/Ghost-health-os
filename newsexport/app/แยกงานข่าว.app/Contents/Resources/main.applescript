-- ============================================================
-- หน้าจอหลักของโปรแกรมแยกงานข่าว
-- ------------------------------------------------------------
-- เป้าหมายของไฟล์นี้
-- ผู้ใช้เปิดงานค้างไว้ใน Final Cut Pro แล้วกดปุ่มเดียว
-- ที่เหลือโปรแกรมทำเองทั้งหมด ผู้ใช้ไม่ต้องเลือกไฟล์ ไม่ต้องเซฟอะไร
--
-- กฎเหล็ก 3 ข้อ
-- 1. ห้ามให้ผู้ใช้เลือกไฟล์ไทม์ไลน์เอง โปรแกรมต้องไปเอามาเอง
-- 2. ห้ามเชื่อว่าการกดแทนสำเร็จ ต้องพิสูจน์ด้วยไฟล์ที่เกิดขึ้นจริง
-- 3. เวลาพัง ต้องบอกให้ชัดว่าพังตรงไหน ห้ามบอกลอย ๆ
-- ============================================================

property appTitle : "แยกงานข่าว"
property fcpName : "Final Cut Pro"

global resourcesPath
global workPath
global prefsPath
global logPath


on run argv
	if (count of argv) > 0 then
		set resourcesPath to item 1 of argv
	else
		set resourcesPath to (do shell script "dirname " & quoted form of (POSIX path of (path to me)))
	end if
	set workPath to (do shell script "mkdir -p ~/Library/Caches/fcpx-news-export && echo ~/Library/Caches/fcpx-news-export")
	set prefsPath to workPath & "/โฟลเดอร์ล่าสุด.txt"
	set logPath to workPath & "/บันทึกการทำงาน.txt"
	startLog()
	showMainMenu()
end run


-- ============================================================
-- ตัวบันทึกการทำงาน
-- ------------------------------------------------------------
-- จดทุกขั้นตอนลงไฟล์ เพื่อว่าถ้าพัง จะรู้ได้ทันทีว่าพังตรงไหน
-- ผู้ใช้ไม่ต้องอธิบายเอง แค่ส่งไฟล์นี้มาก็พอ
-- ============================================================

on startLog()
	try
		do shell script "echo '===== เริ่มรอบใหม่ " & ((current date) as string) & " =====' >> " & quoted form of logPath
	end try
end startLog


on logLine(theText)
	try
		do shell script "echo " & quoted form of ("  " & theText) & " >> " & quoted form of logPath
	end try
end logLine


-- ============================================================
-- หน้าจอหลัก
-- ============================================================

on showMainMenu()
	repeat
		set choice to button returned of (display dialog ¬
			"เปิดงานข่าวค้างไว้ใน Final Cut Pro" & return & ¬
			"แล้วคลิกที่ชื่องานนั้นหนึ่งครั้ง" & return & return & ¬
			"จากนั้นกดปุ่ม เอ็กพอร์ต" & return & return & ¬
			"โปรแกรมจะไปเอาไทม์ไลน์มาเอง แยกเป็นก้อน" & return & ¬
			"แล้วเอ็กพอร์ตให้ครบทุกก้อน ทั้ง mov และ mxf" ¬
			buttons {"ดูบันทึก", "ตรวจสอบระบบ", "เอ็กพอร์ต"} ¬
			default button "เอ็กพอร์ต" with title appTitle)

		if choice is "ดูบันทึก" then
			showLog()
		else if choice is "ตรวจสอบระบบ" then
			runDiagnostics()
		else
			runWorkflow()
		end if
	end repeat
end showMainMenu


on showLog()
	try
		do shell script "open -R " & quoted form of logPath
		display dialog ¬
			"เปิด Finder ให้แล้ว ไฟล์ชื่อ บันทึกการทำงาน.txt" & return & return & ¬
			"ส่งไฟล์นี้กลับมาให้ผม" & return & ¬
			"ผมจะรู้ทันทีว่าติดตรงไหน โดยคุณไม่ต้องอธิบายเลย" ¬
			buttons {"ปิด"} default button 1 with title appTitle
	on error
		display dialog "ยังไม่มีบันทึก ให้ลองกดปุ่ม เอ็กพอร์ต ก่อนหนึ่งครั้ง" ¬
			buttons {"ปิด"} default button 1 with title appTitle
	end try
end showLog


-- ============================================================
-- ลำดับการทำงานทั้งหมด
-- ============================================================

on runWorkflow()
	try
		if not ensureFinalCutRunning() then return
		if not ensureAccessibility() then return

		set outFolder to chooseOutputFolder()
		if outFolder is "" then
			logLine("ผู้ใช้ยกเลิกตอนเลือกโฟลเดอร์")
			return
		end if
		logLine("โฟลเดอร์ปลายทาง = " & outFolder)

		set xmlPath to fetchTimeline(outFolder)
		if xmlPath is "" then
			logLine("จบที่ขั้นไปเอาไทม์ไลน์ ไม่สำเร็จ")
			return
		end if
		logLine("ได้ไทม์ไลน์มาแล้ว = " & xmlPath)

		set gapSeconds to "0.2"
		repeat
			set reportText to runBrief(xmlPath, gapSeconds)
			set answer to button returned of (display dialog ¬
				reportText & return & return & "จำนวนก้อนถูกต้องไหม" ¬
				buttons {"ยกเลิก", "ปรับจำนวนก้อน", "ถูกต้อง เอ็กพอร์ตเลย"} ¬
				default button "ถูกต้อง เอ็กพอร์ตเลย" with title appTitle)
			if answer is "ยกเลิก" then return
			if answer is "ถูกต้อง เอ็กพอร์ตเลย" then exit repeat
			set gapSeconds to askGapSeconds(gapSeconds)
			if gapSeconds is "" then return
		end repeat

		set splitPath to (workPath & "/แยกแล้ว.fcpxml")
		runSplit(xmlPath, gapSeconds, splitPath)
		logLine("แยกงานเสร็จ ใช้ค่าช่องว่าง " & gapSeconds & " วินาที")

		set namesFile to workPath & "/รายชื่อไฟล์.txt"
		do shell script "/usr/bin/env python3 " & quoted form of (resourcesPath & "/tools/fcpxml_segments.py") & ¬
			" " & quoted form of xmlPath & " --min-gap " & gapSeconds & " --names > " & quoted form of namesFile
		set totalFiles to (do shell script "grep -c . " & quoted form of namesFile) as integer

		logLine("ต้องได้ไฟล์ทั้งหมด " & totalFiles & " ไฟล์")

		importTimeline(splitPath)
		logLine("นำงานย่อยกลับเข้า Final Cut Pro แล้ว")

		runExportStage(outFolder, namesFile, totalFiles)
		logLine("จบรอบการทำงาน")

	on error errorMessage number errorNumber
		if errorNumber is -128 then return
		logLine("พังกลางทาง " & errorMessage)
		display dialog ¬
			"เกิดปัญหาระหว่างทำงาน" & return & return & errorMessage & return & return & ¬
			"กดปุ่ม ดูบันทึก ที่หน้าแรก แล้วส่งไฟล์บันทึกมาให้ผม" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
	end try
end runWorkflow


-- ============================================================
-- ตรวจความพร้อม
-- ============================================================

on ensureFinalCutRunning()
	tell application "System Events" to set isRunning to (exists process fcpName)
	if isRunning then return true
	set answer to button returned of (display dialog ¬
		"ยังไม่ได้เปิด Final Cut Pro" & return & return & ¬
		"ให้เปิด Final Cut Pro และเปิดงานข่าวค้างไว้ก่อน" ¬
		buttons {"ยกเลิก", "เปิดให้เลย"} default button "เปิดให้เลย" with title appTitle)
	if answer is "ยกเลิก" then return false
	tell application "Final Cut Pro" to activate
	display dialog ¬
		"เปิด Final Cut Pro แล้ว" & return & return & ¬
		"ให้เปิดงานข่าว แล้วคลิกที่ชื่องานนั้นหนึ่งครั้ง" & return & ¬
		"เสร็จแล้วกดปุ่ม พร้อมแล้ว" ¬
		buttons {"พร้อมแล้ว"} default button 1 with title appTitle
	return true
end ensureFinalCutRunning


on ensureAccessibility()
	try
		tell application "System Events"
			tell process fcpName to get name of menu bar 1
		end tell
		return true
	on error
		set answer to button returned of (display dialog ¬
			"ต้องเปิดสิทธิ์ให้โปรแกรมกดเมนูแทนคุณก่อน ทำครั้งเดียวจบ" & return & return & ¬
			"1. กดปุ่ม เปิดหน้าตั้งค่า ข้างล่างนี้" & return & ¬
			"2. หาชื่อ แยกงานข่าว แล้วเปิดสวิตช์ให้เป็นสีเขียว" & return & ¬
			"3. ถ้าไม่เห็นชื่อ กดปุ่มบวก แล้วเลือกโปรแกรมนี้" & return & ¬
			"4. กลับมาเปิดโปรแกรมนี้ใหม่" ¬
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
	on error number -128
		return ""
	end try
	set chosenPath to POSIX path of chosen
	if chosenPath ends with "/" then set chosenPath to text 1 thru -2 of chosenPath
	do shell script "echo " & quoted form of chosenPath & " > " & quoted form of prefsPath
	return chosenPath
end chooseOutputFolder


-- ============================================================
-- ไปเอาไทม์ไลน์มาเอง ผู้ใช้ไม่ต้องยุ่ง
-- ============================================================

on fetchTimeline(outFolder)
	set marker to workPath & "/เริ่มเมื่อ"
	do shell script "rm -f " & quoted form of marker & " && touch " & quoted form of marker

	-- ตรวจก่อนว่าเมนูกดได้จริงไหม
	-- ถ้าเมนูเป็นสีเทา แปลว่ายังไม่ได้คลิกเลือกชื่องาน ซึ่งเป็นสาเหตุที่พบบ่อยที่สุด
	set state to menuItemState("File", "Export XML")

	if state is "missing" then
		display dialog ¬
			"หาเมนู Export XML ใน Final Cut Pro ไม่เจอ" & return & return & ¬
			"อาจเป็นเพราะเมนูของ Final Cut Pro ไม่ได้เป็นภาษาอังกฤษ" & return & return & ¬
			"กดปุ่ม ตรวจสอบระบบ ที่หน้าแรก แล้วส่งผลมาให้ผมดู" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
		return ""
	end if

	if state is "disabled" then
		display dialog ¬
			"ยังไม่ได้เลือกงานข่าว" & return & return & ¬
			"ใน Final Cut Pro ให้คลิกที่ ชื่องาน หนึ่งครั้ง" & return & ¬
			"คลิกที่ตัวงานในหน้าต่าง Browser" & return & ¬
			"ไม่ใช่คลิกที่ Event หรือ Library" & return & return & ¬
			"คลิกเสร็จแล้วกดปุ่ม เลือกแล้ว" ¬
			buttons {"ยกเลิก", "เลือกแล้ว"} default button "เลือกแล้ว" with title appTitle
		if button returned of result is "ยกเลิก" then return ""
		set state to menuItemState("File", "Export XML")
		if state is not "enabled" then
			display dialog ¬
				"ยังเลือกงานไม่ถูกต้อง" & return & return & ¬
				"ต้องคลิกที่ตัวงานข่าวในหน้าต่าง Browser" & return & ¬
				"ให้ชื่องานมีกรอบสีเหลืองล้อมรอบ" ¬
				buttons {"ปิด"} default button 1 with title appTitle with icon caution
			return ""
		end if
	end if

	display dialog ¬
		"กำลังจะไปอ่านไทม์ไลน์" & return & return & ¬
		"เดี๋ยวจะมีหน้าต่างเซฟของ Final Cut Pro เด้งขึ้นมาแวบหนึ่ง" & return & ¬
		"นั่นคือขั้นตอนภายในของโปรแกรม ไม่ใช่ไฟล์ที่คุณต้องการ" & return & ¬
		"โปรแกรมจะกดปิดเองทันที คุณไม่ต้องทำอะไร" & return & return & ¬
		"ไฟล์ mov และ mxf ที่คุณต้องการ จะได้ในขั้นตอนถัดไป" & return & return & ¬
		"ระหว่างนี้อย่าแตะเมาส์หรือคีย์บอร์ด" ¬
		buttons {"เข้าใจแล้ว เริ่มเลย"} default button 1 with title appTitle

	-- กดเมนู แล้วกดปุ่มยืนยันในหน้าต่างที่เด้งขึ้นมา
	-- ไม่ไปยุ่งกับที่เก็บไฟล์เลย ปล่อยให้มันเซฟตรงไหนก็ได้
	-- เดี๋ยวเราไปตามหาไฟล์เอง ซึ่งทนทานกว่าการบังคับหน้าต่างมาก
	logLine("กดเมนู Export XML")
	try
		clickMenuItem("File", "Export XML")
		delay 2
		confirmSheet()
		logLine("กดปุ่มยืนยันในหน้าต่างเซฟแล้ว")
	on error e
		logLine("กดเมนูไม่สำเร็จ " & e)
	end try

	set foundPath to waitForNewTimeline(marker, outFolder, 20)
	if foundPath is not "" then return foundPath

	-- ยังไม่ได้ ลองกดปุ่มยืนยันซ้ำอีกครั้ง เผื่อหน้าต่างเพิ่งโผล่ช้า
	logLine("ยังไม่เจอไฟล์ ลองกดยืนยันซ้ำ")
	try
		confirmSheet()
	end try
	set foundPath to waitForNewTimeline(marker, outFolder, 25)
	if foundPath is not "" then return foundPath

	-- ทางออกสุดท้าย ให้ผู้ใช้ชี้ตำแหน่งเอง ใช้เวลาไม่กี่วินาที
	-- ดีกว่าปล่อยให้จบแบบทำอะไรต่อไม่ได้
	set answer to button returned of (display dialog ¬
		"หาไฟล์ที่ Final Cut Pro เพิ่งเซฟไม่เจอ" & return & return & ¬
		"มักเกิดตอนเซฟลงไดรฟ์เครือข่าย" & return & return & ¬
		"กดปุ่ม ชี้ให้ดู แล้วเลือกไฟล์ที่เพิ่งเซฟ" & return & ¬
		"ทำครั้งเดียว แล้วโปรแกรมจะไปต่อได้เลย" ¬
		buttons {"ยกเลิก", "ชี้ให้ดู"} default button "ชี้ให้ดู" with title appTitle)
	if answer is "ยกเลิก" then
		logLine("ผู้ใช้ยกเลิกตอนหาไฟล์ไม่เจอ")
		return ""
	end if
	try
		set picked to POSIX path of (choose file with prompt ¬
			"เลือกไฟล์ที่ Final Cut Pro เพิ่งเซฟ ลงท้ายด้วย fcpxml หรือ fcpxmld")
		logLine("ผู้ใช้ชี้ไฟล์เอง " & picked)
		return picked
	on error
		logLine("ผู้ใช้ไม่ได้เลือกไฟล์")
		return ""
	end try
end fetchTimeline


on waitForNewTimeline(marker, outFolder, maxTries)
	-- ค้นหาไฟล์ที่ Final Cut Pro เพิ่งเซฟ
	-- ส่งโฟลเดอร์ปลายทางเข้าไปด้วย เพราะห้องข่าวทำงานบนไดรฟ์เครือข่าย
	-- ซึ่งมักเป็นที่เดียวกับที่ Final Cut Pro จำไว้เป็นที่เซฟล่าสุด
	repeat with i from 1 to maxTries
		try
			set found to do shell script "/usr/bin/env python3 " & ¬
				quoted form of (resourcesPath & "/tools/find_recent.py") & ¬
				" " & quoted form of marker & ¬
				" " & quoted form of outFolder & ¬
				" " & quoted form of workPath
			if found is not "" then
				logLine("เจอไฟล์ไทม์ไลน์ที่ " & found)
				delay 1.5 -- เผื่อเวลาให้เขียนไฟล์เสร็จ
				return found
			end if
		end try
		if i is 5 then logLine("ยังหาไม่เจอ ผ่านไป 5 รอบ กำลังค้นต่อ")
		if i is 15 then logLine("ยังหาไม่เจอ ผ่านไป 15 รอบ กำลังค้นไดรฟ์ที่ต่ออยู่")
		delay 1
	end repeat
	logLine("ค้นครบ " & maxTries & " รอบแล้วยังไม่เจอ")
	return ""
end waitForNewTimeline


on confirmSheet()
	-- กดปุ่มยืนยันในหน้าต่างเซฟ โดยไม่แตะที่เก็บไฟล์
	tell application "System Events"
		tell process fcpName
			set frontmost to true
			delay 0.3
			set didClick to false
			try
				repeat with sheetRef in sheets of window 1
					repeat with buttonName in {"Save", "Export", "OK"}
						try
							click button buttonName of sheetRef
							set didClick to true
							exit repeat
						end try
					end repeat
					if didClick then exit repeat
				end repeat
			end try
			if not didClick then key code 36 -- ปุ่ม Return
		end tell
	end tell
end confirmSheet


-- ============================================================
-- นำงานย่อยกลับเข้า Final Cut Pro
-- ============================================================

on importTimeline(splitPath)
	-- วิธีนี้เชื่อถือได้กว่าการกดเมนูมาก
	-- เพราะเป็นการบอก macOS ให้เปิดไฟล์ด้วย Final Cut Pro ตรง ๆ
	-- Final Cut Pro จะนำเข้าให้เองโดยไม่ต้องกดปุ่มอะไรเลย
	do shell script "open -a " & quoted form of "/Applications/Final Cut Pro.app" & " " & quoted form of splitPath
	delay 3

	display dialog ¬
		"แยกงานเรียบร้อยแล้ว" & return & return & ¬
		"งานย่อยกำลังเข้าไปอยู่ใน Final Cut Pro" & return & ¬
		"ชื่อลงท้าย -1 -2 -3 เรียงตามลำดับให้แล้ว" & return & return & ¬
		"ถ้ามีหน้าต่างถามเรื่องการนำเข้า ให้กด Import" & return & ¬
		"เสร็จแล้วกดปุ่มข้างล่าง" ¬
		buttons {"เข้ามาแล้ว"} default button 1 with title appTitle
end importTimeline


-- ============================================================
-- เอ็กพอร์ต พร้อมแสดงเปอร์เซ็นต์
-- ============================================================

on runExportStage(outFolder, namesFile, totalFiles)
	display dialog ¬
		"ขั้นสุดท้าย" & return & return & ¬
		"ให้เลือกงานย่อยทั้งหมดพร้อมกัน" & return & ¬
		"คลิกอันแรก กด Shift ค้าง แล้วคลิกอันสุดท้าย" & return & return & ¬
		"ไฟล์จะถูกเก็บไว้ที่" & return & outFolder ¬
		buttons {"เลือกแล้ว ไปต่อ"} default button 1 with title appTitle

	logLine("เริ่มขั้นเอ็กพอร์ต")
	shareWith("Export File", "ไฟล์ mov", outFolder)
	shareWith("MXF-50", "ไฟล์ mxf", outFolder)
	monitorProgress(outFolder, namesFile, totalFiles)
end runExportStage


on shareWith(destinationName, humanName, outFolder)
	set opened to false
	try
		tell application "System Events"
			tell process fcpName
				set frontmost to true
				delay 0.4
				set fileMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "File")
				set shareItem to (first menu item of fileMenu whose name starts with "Share")
				click (first menu item of menu 1 of shareItem whose name starts with destinationName)
				set opened to true
			end tell
		end tell
		delay 2.5
		logLine("เปิดหน้าต่าง Share " & destinationName & " สำเร็จ")
	on error e
		logLine("เปิดหน้าต่าง Share " & destinationName & " ไม่สำเร็จ " & e)
	end try

	if opened then
		display dialog ¬
			"หน้าต่างตั้งค่า " & humanName & " เปิดขึ้นมาแล้ว" & return & return & ¬
			"กดปุ่ม Next แล้วเลือกโฟลเดอร์นี้" & return & return & outFolder & return & return & ¬
			"สั่งเอ็กพอร์ตแล้วกดปุ่มข้างล่าง" ¬
			buttons {"สั่งแล้ว"} default button 1 with title appTitle
	else
		display dialog ¬
			"เปิดหน้าต่าง " & humanName & " ให้ไม่สำเร็จ" & return & return & ¬
			"ขอให้ทำเอง ไปที่เมนู File แล้ว Share" & return & ¬
			"แล้วเลือก " & destinationName & return & return & ¬
			"เก็บไฟล์ไว้ที่" & return & outFolder ¬
			buttons {"สั่งแล้ว"} default button 1 with title appTitle
	end if
end shareWith


on monitorProgress(outFolder, namesFile, totalFiles)
	set stillWaiting to true
	set lastDone to -1

	repeat while stillWaiting
		set report to do shell script "/usr/bin/env python3 " & ¬
			quoted form of (resourcesPath & "/tools/watch_outputs.py") & ¬
			" " & quoted form of outFolder & " " & quoted form of namesFile
		set parts to paragraphs of report
		set doneCount to (item 1 of parts) as integer
		set workingCount to (item 2 of parts) as integer
		set lastName to item 4 of parts

		if doneCount ≥ totalFiles then exit repeat

		set percent to 0
		if totalFiles > 0 then set percent to round (doneCount * 100 / totalFiles)

		if doneCount > lastDone then
			try
				display notification "เสร็จแล้ว " & doneCount & " จาก " & totalFiles & " ไฟล์" ¬
					with title appTitle subtitle ((percent as string) & "%")
			end try
			set lastDone to doneCount
		end if

		set statusLine to "กำลังรอ Final Cut Pro เริ่มสร้างไฟล์"
		if workingCount > 0 then set statusLine to "กำลังเขียนอยู่ " & workingCount & " ไฟล์"

		set message to "กำลังเอ็กพอร์ต" & return & return & ¬
			progressBar(percent) & "  " & percent & "%" & return & return & ¬
			"เสร็จแล้ว " & doneCount & " จาก " & totalFiles & " ไฟล์" & return & statusLine
		if lastName is not "" then
			set message to message & return & return & "ไฟล์ล่าสุด" & return & lastName
		end if

		set reply to display dialog message ¬
			buttons {"หยุดรอ", "เปิดโฟลเดอร์"} default button "หยุดรอ" ¬
			giving up after 3 with title appTitle
		if gave up of reply is false then
			if button returned of reply is "เปิดโฟลเดอร์" then
				do shell script "open " & quoted form of outFolder
			else
				set stillWaiting to false
			end if
		end if
	end repeat

	finishDialog(outFolder, totalFiles, stillWaiting)
end monitorProgress


on progressBar(percent)
	set filled to round (percent / 5)
	if filled < 0 then set filled to 0
	if filled > 20 then set filled to 20
	set bar to ""
	repeat with i from 1 to 20
		if i ≤ filled then
			set bar to bar & "█"
		else
			set bar to bar & "░"
		end if
	end repeat
	return bar
end progressBar


on finishDialog(outFolder, totalFiles, wasCompleted)
	if wasCompleted then
		set headline to "เสร็จเรียบร้อย ได้ไฟล์ครบ " & totalFiles & " ไฟล์แล้ว"
		logLine("สำเร็จ ได้ไฟล์ครบ " & totalFiles & " ไฟล์")
	else
		set headline to "หยุดรอแล้ว Final Cut Pro อาจยังสร้างไฟล์ต่ออยู่"
		logLine("ผู้ใช้กดหยุดรอ")
	end if
	set answer to button returned of (display dialog ¬
		headline & return & return & "ไฟล์ทั้งหมดอยู่ที่" & return & return & outFolder ¬
		buttons {"ปิด", "เปิดโฟลเดอร์"} default button "เปิดโฟลเดอร์" with title appTitle)
	if answer is "เปิดโฟลเดอร์" then do shell script "open " & quoted form of outFolder
end finishDialog


-- ============================================================
-- ตรวจสอบระบบ บอกให้ชัดว่าอะไรพร้อมอะไรไม่พร้อม
-- ============================================================

on runDiagnostics()
	set lines to {}

	-- Final Cut Pro เปิดอยู่ไหม
	tell application "System Events" to set isRunning to (exists process fcpName)
	if isRunning then
		set end of lines to "เปิด Final Cut Pro อยู่          ผ่าน"
	else
		set end of lines to "เปิด Final Cut Pro อยู่          ไม่ผ่าน ยังไม่ได้เปิด"
	end if

	-- สิทธิ์กดเมนูแทนผู้ใช้
	set canSeeMenus to false
	try
		tell application "System Events"
			tell process fcpName to get name of menu bar 1
		end tell
		set canSeeMenus to true
		set end of lines to "สิทธิ์กดเมนูแทน               ผ่าน"
	on error
		set end of lines to "สิทธิ์กดเมนูแทน               ไม่ผ่าน ต้องเปิดสิทธิ์ก่อน"
	end try

	if canSeeMenus then
		-- เมนูที่ต้องใช้ มีครบไหม และกดได้ไหม
		set end of lines to "เมนู Export XML              " & thaiState(menuItemState("File", "Export XML"))
		set end of lines to "เมนู Share ปลายทาง mov       " & thaiState(shareItemState("Export File"))
		set end of lines to "เมนู Share ปลายทาง mxf       " & thaiState(shareItemState("MXF-50"))
	end if

	-- ตัวช่วยที่ต้องใช้
	try
		do shell script "/usr/bin/env python3 --version"
		set end of lines to "ตัวช่วย python3               ผ่าน"
	on error
		set end of lines to "ตัวช่วย python3               ไม่ผ่าน"
	end try

	set report to ""
	repeat with aLine in lines
		set report to report & aLine & return
	end repeat

	set answer to button returned of (display dialog ¬
		"ผลตรวจสอบระบบ" & return & return & report & return & ¬
		"คำอธิบาย" & return & ¬
		"กดไม่ได้ แปลว่ายังไม่ได้คลิกเลือกชื่องานข่าว" & return & ¬
		"ไม่มีเมนูนี้ แปลว่าชื่อเมนูไม่ตรง ต้องแจ้งผมให้แก้" ¬
		buttons {"ปิด", "คัดลอกผล"} default button "ปิด" with title appTitle)
	if answer is "คัดลอกผล" then
		set the clipboard to report
		display dialog "คัดลอกแล้ว วางส่งกลับมาได้เลย" buttons {"ปิด"} default button 1 with title appTitle
	end if
end runDiagnostics


on thaiState(state)
	if state is "enabled" then return "ผ่าน"
	if state is "disabled" then return "กดไม่ได้ ยังไม่ได้เลือกงาน"
	return "ไม่มีเมนูนี้"
end thaiState


on shareItemState(destinationName)
	try
		tell application "System Events"
			tell process fcpName
				set fileMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "File")
				set shareItem to (first menu item of fileMenu whose name starts with "Share")
				set target to (first menu item of menu 1 of shareItem whose name starts with destinationName)
				if enabled of target then return "enabled"
				return "disabled"
			end tell
		end tell
	on error
		return "missing"
	end try
end shareItemState


-- ============================================================
-- ตัวช่วยกดเมนู
-- ============================================================

on menuItemState(menuName, itemPrefix)
	-- คืนค่าได้ 3 แบบ  enabled คือกดได้  disabled คือเป็นสีเทา  missing คือไม่มีเมนูนี้
	try
		tell application "System Events"
			tell process fcpName
				set frontmost to true
				delay 0.3
				set target to (first menu item of menu 1 of (first menu bar item of menu bar 1 whose name is menuName) whose name starts with itemPrefix)
				if enabled of target then return "enabled"
				return "disabled"
			end tell
		end tell
	on error
		return "missing"
	end try
end menuItemState


on clickMenuItem(menuName, itemPrefix)
	tell application "System Events"
		tell process fcpName
			set frontmost to true
			delay 0.4
			click (first menu item of menu 1 of (first menu bar item of menu bar 1 whose name is menuName) whose name starts with itemPrefix)
		end tell
	end tell
end clickMenuItem


-- ============================================================
-- ตัวช่วยเรียกโปรแกรมอ่านและแยกไทม์ไลน์
-- ============================================================

on runBrief(inputPath, gapSeconds)
	return do shell script "/usr/bin/env python3 " & ¬
		quoted form of (resourcesPath & "/tools/fcpxml_segments.py") & ¬
		" " & quoted form of inputPath & " --min-gap " & gapSeconds & " --brief"
end runBrief


on runSplit(inputPath, gapSeconds, outputPath)
	return do shell script "/usr/bin/env python3 " & ¬
		quoted form of (resourcesPath & "/tools/fcpxml_split.py") & ¬
		" " & quoted form of inputPath & " --min-gap " & gapSeconds & ¬
		" -o " & quoted form of outputPath
end runSplit


on askGapSeconds(currentValue)
	try
		return text returned of (display dialog ¬
			"ปรับจำนวนก้อน" & return & return & ¬
			"ได้ก้อนน้อยเกินไป ให้ลดตัวเลขลง เช่น 0.1" & return & ¬
			"ได้ก้อนเยอะเกินไป ให้เพิ่มตัวเลขขึ้น เช่น 1 หรือ 2" & return & return & ¬
			"ตัวเลขนี้คือ ช่องว่างกี่วินาทีจึงนับว่าคั่นข่าวคนละเรื่อง" ¬
			default answer currentValue ¬
			buttons {"ยกเลิก", "ลองใหม่"} default button "ลองใหม่" with title appTitle)
	on error
		return ""
	end try
end askGapSeconds
