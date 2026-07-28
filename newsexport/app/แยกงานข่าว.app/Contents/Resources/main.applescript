-- ============================================================
-- หน้าจอหลักของโปรแกรมแยกงานข่าว
-- ------------------------------------------------------------
-- Final Cut Pro ไม่เปิดให้สั่งงานจากภายนอกโดยตรง
-- โปรแกรมจึงต้องกดเมนูแทนผู้ใช้ผ่านระบบช่วยเหลือของ macOS
--
-- กฎเหล็กของไฟล์นี้
-- ห้ามเชื่อว่าการกดแทนสำเร็จ ต้องพิสูจน์ด้วยไฟล์ที่เกิดขึ้นจริงเท่านั้น
-- ถ้าพิสูจน์ไม่ได้ ต้องบอกผู้ใช้ให้ทำเอง แล้วรอต่อ ห้ามจบด้วยความล้มเหลว
-- ============================================================

property appTitle : "แยกงานข่าว"
property fcpName : "Final Cut Pro"

global resourcesPath
global workPath
global prefsPath


on run argv
	if (count of argv) > 0 then
		set resourcesPath to item 1 of argv
	else
		set resourcesPath to (do shell script "dirname " & quoted form of (POSIX path of (path to me)))
	end if
	set workPath to (do shell script "mkdir -p ~/Library/Caches/fcpx-news-export && echo ~/Library/Caches/fcpx-news-export")
	set prefsPath to workPath & "/โฟลเดอร์ล่าสุด.txt"
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
			"เปิดงานข่าวค้างไว้ใน Final Cut Pro" & return & ¬
			"แล้วคลิกที่ชื่องานนั้นหนึ่งครั้ง" & return & return & ¬
			"จากนั้นกดปุ่ม เริ่มทำงาน" ¬
			buttons {"ปิด", "วิธีใช้", "เริ่มทำงาน"} ¬
			default button "เริ่มทำงาน" with title appTitle)

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
		"โปรแกรมทำให้ 5 ขั้น" & return & return & ¬
		"1. ถามว่าจะเก็บไฟล์ไว้ที่ไหน" & return & ¬
		"2. ดึงไทม์ไลน์ออกมาจาก Final Cut Pro" & return & ¬
		"3. บอกว่าพบข่าวกี่ก้อน ให้ตรวจก่อน" & return & ¬
		"4. แยกเป็นงานย่อย ตั้งชื่อลงท้าย -1 -2 -3 ให้เอง" & return & ¬
		"5. ช่วยเอ็กพอร์ต พร้อมแสดงเปอร์เซ็นต์จนเสร็จ" & return & return & ¬
		"สิ่งที่โปรแกรมไม่ทำ" & return & return & ¬
		"ไม่แก้งานเดิมของคุณ อ่านอย่างเดียว" & return & ¬
		"ไม่แปลงไฟล์เอง เสียงและ Roles จึงไม่เพี้ยน" & return & ¬
		"ไม่สร้างไฟล์ใด ๆ จนกว่าคุณจะกดยืนยัน" ¬
		buttons {"เข้าใจแล้ว"} default button 1 with title appTitle
end showHelp


-- ============================================================
-- ลำดับการทำงานทั้งหมด
-- ============================================================

on runWorkflow()
	try
		if not ensureFinalCutRunning() then return
		if not ensureAccessibility() then return

		-- ขั้นที่ 1 เลือกโฟลเดอร์เก็บไฟล์
		set outFolder to chooseOutputFolder()
		if outFolder is "" then return

		-- ขั้นที่ 2 ดึงไทม์ไลน์ออกมา
		set xmlPath to exportTimeline()
		if xmlPath is "" then return

		-- ขั้นที่ 3 ตรวจจำนวนก้อน
		set gapSeconds to "0.2"
		repeat
			set reportText to runBrief(xmlPath, gapSeconds)
			set answer to button returned of (display dialog ¬
				reportText & return & return & "รายการนี้ถูกต้องไหม" ¬
				buttons {"ยกเลิก", "ปรับจำนวนก้อน", "ถูกต้อง ไปต่อ"} ¬
				default button "ถูกต้อง ไปต่อ" with title appTitle)
			if answer is "ยกเลิก" then return
			if answer is "ถูกต้อง ไปต่อ" then exit repeat
			set gapSeconds to askGapSeconds(gapSeconds)
			if gapSeconds is "" then return
		end repeat

		-- ขั้นที่ 4 แยกงานแล้วนำกลับเข้า Final Cut Pro
		set splitPath to (workPath & "/แยกแล้ว.fcpxml")
		runSplit(xmlPath, gapSeconds, splitPath)

		-- เก็บรายชื่อไฟล์ที่ต้องได้ ไว้ใช้นับเปอร์เซ็นต์ตอนเอ็กพอร์ต
		set namesFile to workPath & "/รายชื่อไฟล์.txt"
		do shell script "/usr/bin/env python3 " & quoted form of (resourcesPath & "/tools/fcpxml_segments.py") & ¬
			" " & quoted form of xmlPath & " --min-gap " & gapSeconds & " --names > " & quoted form of namesFile
		set totalFiles to (do shell script "grep -c . " & quoted form of namesFile) as integer

		importTimeline(splitPath)

		-- ขั้นที่ 5 เอ็กพอร์ตพร้อมแสดงเปอร์เซ็นต์
		runExportStage(outFolder, namesFile, totalFiles)

	on error errorMessage number errorNumber
		if errorNumber is -128 then return
		display dialog ¬
			"เกิดปัญหาระหว่างทำงาน" & return & return & errorMessage & return & return & ¬
			"ถ้าไม่เข้าใจข้อความนี้ ถ่ายรูปหน้าจอส่งกลับมาได้เลย" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
	end try
end runWorkflow


-- ============================================================
-- ขั้นที่ 0 ตรวจความพร้อม
-- ============================================================

on ensureFinalCutRunning()
	tell application "System Events" to set isRunning to (exists process fcpName)
	if isRunning then return true
	set answer to button returned of (display dialog ¬
		"ยังไม่ได้เปิด Final Cut Pro" & return & return & ¬
		"ให้เปิด Final Cut Pro และเปิดงานข่าวที่ต้องการค้างไว้ก่อน" ¬
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


-- ============================================================
-- ขั้นที่ 1 เลือกโฟลเดอร์เก็บไฟล์
-- ============================================================

on chooseOutputFolder()
	-- จำโฟลเดอร์ที่เลือกครั้งก่อน เพื่อไม่ต้องหาใหม่ทุกวัน
	set startFolder to missing value
	try
		set lastFolder to (do shell script "cat " & quoted form of prefsPath)
		if lastFolder is not "" then
			set startFolder to (POSIX file lastFolder) as alias
		end if
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
	-- ตัดขีดปิดท้ายออก เพื่อให้เอาไปต่อชื่อไฟล์ได้สะดวก
	if chosenPath ends with "/" then
		set chosenPath to text 1 thru -2 of chosenPath
	end if
	do shell script "echo " & quoted form of chosenPath & " > " & quoted form of prefsPath
	return chosenPath
end chooseOutputFolder


-- ============================================================
-- ขั้นที่ 2 ดึงไทม์ไลน์ออกมาจาก Final Cut Pro
-- ============================================================

on exportTimeline()
	set outFolder to workPath & "/ดึงออกมา"
	do shell script "rm -rf " & quoted form of outFolder & " && mkdir -p " & quoted form of outFolder
	-- จำเวลาเริ่ม เพื่อใช้ค้นหาไฟล์ที่เพิ่งเกิดใหม่ในที่อื่น ๆ
	set startStamp to workPath & "/เริ่มเมื่อ"
	do shell script "touch " & quoted form of startStamp

	display dialog ¬
		"ขั้นที่ 2 จาก 5" & return & return & ¬
		"กำลังจะดึงไทม์ไลน์ออกมาจาก Final Cut Pro" & return & return & ¬
		"ตรวจก่อนว่าคลิกเลือกชื่องานข่าวไว้แล้ว" & return & ¬
		"ระหว่างนี้อย่าเพิ่งแตะเมาส์หรือคีย์บอร์ด" ¬
		buttons {"เริ่มเลย"} default button 1 with title appTitle

	-- ครั้งที่หนึ่ง ลองกดแทนให้
	try
		clickMenuItem("File", "Export XML")
		delay 2
		if sheetIsOpen() then
			saveSheetTo(outFolder, "ไทม์ไลน์")
		end if
	end try

	set foundPath to findTimelineFile(outFolder, startStamp, 25)
	if foundPath is not "" then return foundPath

	-- ครั้งที่สอง ให้ผู้ใช้ทำเอง โปรแกรมเปิดโฟลเดอร์รอไว้ให้แล้ว
	do shell script "open " & quoted form of outFolder
	display dialog ¬
		"กดแทนให้ไม่สำเร็จ ขอให้ทำเอง 2 ขั้นตอนนี้" & return & return & ¬
		"1. กลับไปที่ Final Cut Pro คลิกที่ชื่องานข่าว" & return & ¬
		"   แล้วไปที่เมนู File เลือก Export XML" & return & return & ¬
		"2. เซฟลงในโฟลเดอร์ที่เพิ่งเปิดขึ้นมาให้" & return & ¬
		"   หรือจะเซฟที่ Desktop ก็ได้ โปรแกรมหาเจอเอง" & return & return & ¬
		"เซฟเสร็จแล้วค่อยกดปุ่มข้างล่าง" ¬
		buttons {"เซฟแล้ว"} default button 1 with title appTitle

	set foundPath to findTimelineFile(outFolder, startStamp, 90)
	if foundPath is not "" then return foundPath

	display dialog ¬
		"ยังหาไฟล์ไทม์ไลน์ไม่เจอ" & return & return & ¬
		"สาเหตุที่พบบ่อยที่สุดคือ ไม่ได้คลิกเลือกชื่องานข่าวก่อน" & return & ¬
		"ต้องคลิกที่ตัวงาน ไม่ใช่ที่ Event หรือ Library" & return & return & ¬
		"ลองใหม่อีกครั้งได้เลย" ¬
		buttons {"ปิด"} default button 1 with title appTitle with icon caution
	return ""
end exportTimeline


on findTimelineFile(outFolder, startStamp, maxSeconds)
	-- หาไฟล์ที่เกิดใหม่ ทั้งในโฟลเดอร์ที่เตรียมไว้ และในที่ที่คนชอบเซฟกัน
	repeat with i from 1 to maxSeconds
		try
			set found to do shell script ¬
				"find " & quoted form of outFolder & " -maxdepth 1 \\( -name '*.fcpxmld' -o -name '*.fcpxml' \\) -newer " & quoted form of startStamp & " 2>/dev/null | head -1"
			if found is "" then
				set found to do shell script ¬
					"find ~/Desktop ~/Documents ~/Movies ~/Downloads -maxdepth 2 \\( -name '*.fcpxmld' -o -name '*.fcpxml' \\) -newer " & quoted form of startStamp & " 2>/dev/null | head -1"
			end if
			if found is not "" then
				delay 1.5 -- เผื่อเวลาให้เขียนไฟล์เสร็จสมบูรณ์
				return found
			end if
		end try
		delay 1
	end repeat
	return ""
end findTimelineFile


-- ============================================================
-- ขั้นที่ 4 นำงานย่อยกลับเข้า Final Cut Pro
-- ============================================================

on importTimeline(splitPath)
	display dialog ¬
		"ขั้นที่ 4 จาก 5" & return & return & ¬
		"แยกงานเรียบร้อยแล้ว" & return & ¬
		"กำลังจะนำงานย่อยกลับเข้า Final Cut Pro" & return & return & ¬
		"ระหว่างนี้อย่าเพิ่งแตะเมาส์หรือคีย์บอร์ด" ¬
		buttons {"ไปต่อ"} default button 1 with title appTitle

	set didOpen to false
	try
		tell application "System Events"
			tell process fcpName
				set frontmost to true
				delay 0.4
				set fileMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "File")
				set importItem to (first menu item of fileMenu whose name starts with "Import")
				click (first menu item of menu 1 of importItem whose name starts with "XML")
			end tell
		end tell
		delay 2
		if sheetIsOpen() then
			openSheetAt(splitPath)
			set didOpen to true
		end if
	end try

	if not didOpen then
		do shell script "open -R " & quoted form of splitPath
		display dialog ¬
			"กดแทนให้ไม่สำเร็จ ขอให้ทำเอง 2 ขั้นตอนนี้" & return & return & ¬
			"1. ใน Final Cut Pro ไปที่เมนู File แล้ว Import แล้ว XML" & return & return & ¬
			"2. เลือกไฟล์ แยกแล้ว.fcpxml ที่เปิดค้างไว้ให้ใน Finder" & return & return & ¬
			"เสร็จแล้วกดปุ่มข้างล่าง" ¬
			buttons {"นำเข้าแล้ว"} default button 1 with title appTitle
	end if
end importTimeline


-- ============================================================
-- ขั้นที่ 5 เอ็กพอร์ต พร้อมแสดงเปอร์เซ็นต์
-- ============================================================

on runExportStage(outFolder, namesFile, totalFiles)
	display dialog ¬
		"ขั้นที่ 5 จาก 5" & return & return & ¬
		"งานย่อยเข้าไปอยู่ใน Final Cut Pro แล้ว" & return & ¬
		"ชื่อลงท้าย -1 -2 -3 เรียงตามลำดับให้แล้ว" & return & return & ¬
		"ให้เลือกงานย่อยทั้งหมดพร้อมกัน" & return & ¬
		"คลิกอันแรก กด Shift ค้าง แล้วคลิกอันสุดท้าย" & return & return & ¬
		"ไฟล์จะถูกเก็บไว้ที่" & return & outFolder ¬
		buttons {"เลือกแล้ว ไปต่อ"} default button 1 with title appTitle

	shareWith("Export File", "ไฟล์ mov", outFolder)
	shareWith("MXF-50", "ไฟล์ mxf", outFolder)

	monitorProgress(outFolder, namesFile, totalFiles)
end runExportStage


on shareWith(destinationName, humanName, outFolder)
	try
		tell application "System Events"
			tell process fcpName
				set frontmost to true
				delay 0.4
				set fileMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "File")
				set shareItem to (first menu item of fileMenu whose name starts with "Share")
				click (first menu item of menu 1 of shareItem whose name starts with destinationName)
			end tell
		end tell
		delay 2.5
	end try

	display dialog ¬
		"กำลังตั้งค่า " & humanName & return & return & ¬
		"ในหน้าต่างของ Final Cut Pro ให้กดปุ่ม Next" & return & ¬
		"แล้วเลือกโฟลเดอร์นี้เป็นที่เก็บไฟล์" & return & return & ¬
		outFolder & return & return & ¬
		"กดปุ่มข้างล่างเมื่อสั่งเอ็กพอร์ตแล้ว" ¬
		buttons {"สั่งแล้ว"} default button 1 with title appTitle
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

		-- แจ้งเตือนแบบไม่รบกวน เมื่อมีไฟล์เสร็จเพิ่ม
		if doneCount > lastDone then
			try
				display notification "เสร็จแล้ว " & doneCount & " จาก " & totalFiles & " ไฟล์" ¬
					with title appTitle subtitle (percent & "%")
			end try
			set lastDone to doneCount
		end if

		set statusLine to "กำลังรอ Final Cut Pro เริ่มสร้างไฟล์"
		if workingCount > 0 then set statusLine to "กำลังเขียนอยู่ " & workingCount & " ไฟล์"

		set message to ¬
			"กำลังเอ็กพอร์ต" & return & return & ¬
			progressBar(percent) & "  " & percent & "%" & return & return & ¬
			"เสร็จแล้ว " & doneCount & " จาก " & totalFiles & " ไฟล์" & return & ¬
			statusLine
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
	-- แถบความคืบหน้าแบบตัวอักษร ยาว 20 ช่อง
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
	else
		set headline to "หยุดรอแล้ว Final Cut Pro อาจยังสร้างไฟล์ต่ออยู่"
	end if

	set answer to button returned of (display dialog ¬
		headline & return & return & ¬
		"ไฟล์ทั้งหมดถูกเก็บไว้ที่" & return & return & outFolder ¬
		buttons {"ปิด", "เปิดโฟลเดอร์"} default button "เปิดโฟลเดอร์" with title appTitle)
	if answer is "เปิดโฟลเดอร์" then
		do shell script "open " & quoted form of outFolder
	end if
end finishDialog


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


on sheetIsOpen()
	-- ตรวจว่าหน้าต่างเซฟหรือเปิดไฟล์โผล่ขึ้นมาจริงหรือยัง
	-- ถ้าไม่ตรวจ แล้วพิมพ์ลงไปเลย ตัวอักษรจะไปตกใส่ไทม์ไลน์ ซึ่งอันตราย
	try
		tell application "System Events"
			tell process fcpName
				if (count of sheets of window 1) > 0 then return true
			end tell
		end tell
	end try
	return false
end sheetIsOpen


on saveSheetTo(folderPath, fileName)
	tell application "System Events"
		tell process fcpName
			set frontmost to true
			keystroke "g" using {command down, shift down}
			delay 1
			keystroke folderPath
			delay 0.6
			key code 36
			delay 1.2
			keystroke "a" using {command down}
			delay 0.3
			keystroke fileName
			delay 0.5
			key code 36
		end tell
	end tell
end saveSheetTo


on openSheetAt(filePath)
	tell application "System Events"
		tell process fcpName
			set frontmost to true
			keystroke "g" using {command down, shift down}
			delay 1
			keystroke filePath
			delay 0.6
			key code 36
			delay 1.5
			key code 36
		end tell
	end tell
end openSheetAt


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
