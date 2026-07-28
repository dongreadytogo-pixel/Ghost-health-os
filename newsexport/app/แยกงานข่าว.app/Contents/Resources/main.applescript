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
			buttons {"ดูบันทึก", "ทดสอบละเอียด", "เอ็กพอร์ต"} ¬
			default button "เอ็กพอร์ต" with title appTitle)

		if choice is "ดูบันทึก" then
			showLog()
		else if choice is "ทดสอบละเอียด" then
			runDeepTest()
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
		-- ตั้งชื่อ Event ไม่ให้ซ้ำของเดิม กันงานเก่าปนกับงานใหม่
		set eventName to "แยกงาน " & (do shell script "date +%d-%m' '%H%M")
		runSplit(xmlPath, gapSeconds, splitPath, eventName)
		logLine("Event ที่จะนำเข้าชื่อ " & eventName)
		logLine("แยกงานเสร็จ ใช้ค่าช่องว่าง " & gapSeconds & " วินาที")

		set namesFile to workPath & "/รายชื่อไฟล์.txt"
		do shell script "/usr/bin/env python3 " & quoted form of (resourcesPath & "/tools/fcpxml_segments.py") & ¬
			" " & quoted form of xmlPath & " --min-gap " & gapSeconds & " --names > " & quoted form of namesFile
		set totalFiles to (do shell script "grep -c . " & quoted form of namesFile) as integer

		logLine("ต้องได้ไฟล์ทั้งหมด " & totalFiles & " ไฟล์")

		-- อ่านข้อมูลครบแล้ว ไฟล์ไทม์ไลน์ชั่วคราวไม่ต้องใช้อีก
		-- ลบทิ้งทันที ผู้ใช้จะได้ไม่มีไฟล์ fcpxmld ค้างเกลื่อนไดรฟ์
		cleanUpTempTimeline(xmlPath)

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
		"เลือกโฟลเดอร์เรียบร้อย ต่อจากนี้โปรแกรมทำเองทั้งหมด" & return & return & ¬
		"จะมีหน้าต่างของ Final Cut Pro เด้งขึ้นมาหลายอัน" & return & ¬
		"ทั้งหมดเป็นขั้นตอนภายใน โปรแกรมจะกดให้เอง" & return & return & ¬
		"สำคัญที่สุด ระหว่างนี้อย่าแตะเมาส์และคีย์บอร์ดเลย" & return & ¬
		"เพราะโปรแกรมกำลังกดปุ่มแทนคุณอยู่" & return & return & ¬
		"ใช้เวลาประมาณหนึ่งถึงสองนาที" ¬
		buttons {"เริ่มเลย"} default button 1 with title appTitle

	-- กดเมนู แล้วกดปุ่มยืนยันในหน้าต่างที่เด้งขึ้นมา
	-- ไม่ไปยุ่งกับที่เก็บไฟล์เลย ปล่อยให้มันเซฟตรงไหนก็ได้
	-- เดี๋ยวเราไปตามหาไฟล์เอง ซึ่งทนทานกว่าการบังคับหน้าต่างมาก
	-- ตั้งชื่อไฟล์ชั่วคราวไม่ซ้ำใคร ด้วยเวลาปัจจุบัน
	-- ทำแบบนี้เพื่อสองอย่าง
	-- หนึ่ง ไม่ไปชนไฟล์ชื่อเดิม จึงไม่มีหน้าต่างถามว่าจะเขียนทับไหม
	-- สอง เรารู้ชื่อไฟล์แน่นอน จึงตามหาเจอทันที ไม่ต้องเดา
	set stamp to do shell script "date +%Y%m%d-%H%M%S"
	set tempName to "ghostexport-" & stamp

	logLine("กดเมนู Export XML ตั้งชื่อชั่วคราวว่า " & tempName)
	try
		clickMenuItem("File", "Export XML")
		-- ต้องรอให้หน้าต่างเซฟโผล่ขึ้นมาจริงก่อน
		-- ถ้าพิมพ์ทั้งที่หน้าต่างยังไม่มา ตัวอักษรจะหายไปเฉย ๆ
		-- แล้วหน้าต่างจะค้างรอให้ผู้ใช้พิมพ์ชื่อเอง ซึ่งเป็นสิ่งที่ต้องไม่เกิด
		if waitForSheet(12) then
			logLine("หน้าต่างเซฟโผล่แล้ว")
			-- บังคับที่เซฟเข้าโฟลเดอร์ของโปรแกรมเอง
			-- ทำได้แล้วเพราะเปลี่ยนมาใช้การวางแทนการพิมพ์
			-- ผลคือรู้ตำแหน่งไฟล์แน่นอน ไม่ต้องกวาดหาทั้งเครื่องซึ่งช้ามาก
			goToFolderSafely(workPath)
			nameAndSaveSheet(tempName)
			logLine("ตั้งชื่อและกดเซฟแล้ว")
		else
			logLine("รอหน้าต่างเซฟ 12 วินาทีแล้วไม่มา")
		end if
	on error e
		logLine("กดเมนูไม่สำเร็จ " & e)
	end try

	-- ดูที่ตำแหน่งที่เราบังคับไว้ก่อน วิธีนี้เร็วที่สุด
	set exactPath to lookInWorkFolder(tempName, 15)
	if exactPath is not "" then return exactPath

	set foundPath to waitForNewTimeline(marker, outFolder, tempName, 15)
	if foundPath is not "" then return foundPath

	-- ยังไม่ได้ ลองปิดหน้าต่างที่อาจค้างอยู่ แล้วรออีกรอบ
	logLine("ยังไม่เจอไฟล์ ลองเคลียร์หน้าต่างที่ค้าง")
	try
		dismissLeftoverSheets()
	end try
	-- ดูที่ตำแหน่งที่เราบังคับไว้ก่อน วิธีนี้เร็วที่สุด
	set exactPath to lookInWorkFolder(tempName, 15)
	if exactPath is not "" then return exactPath

	set foundPath to waitForNewTimeline(marker, outFolder, tempName, 15)
	if foundPath is not "" then return foundPath

	-- ยังไม่เจออีก อาจเป็นเพราะตั้งชื่อไม่ติด ลองหาแบบไม่สนใจชื่อ
	logLine("ลองหาแบบไม่สนใจชื่อไฟล์")
	set foundPath to waitForNewTimeline(marker, outFolder, "", 10)
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


on lookInWorkFolder(tempName, maxTries)
	-- ดูตรง ๆ ในโฟลเดอร์ของโปรแกรม ว่าไฟล์ที่เราตั้งชื่อไว้โผล่มาหรือยัง
	-- ไม่ต้องค้นหาอะไรเลย จึงเร็วมากและไม่มีทางหยิบไฟล์ผิด
	repeat with i from 1 to maxTries
		try
			set found to do shell script ¬
				"ls -d " & quoted form of (workPath & "/" & tempName & ".fcpxmld") & ¬
				" " & quoted form of (workPath & "/" & tempName & ".fcpxml") & ¬
				" 2>/dev/null | head -1"
			if found is not "" then
				logLine("เจอไฟล์ที่ตำแหน่งที่บังคับไว้ " & found)
				delay 1
				return found
			end if
		end try
		delay 1
	end repeat
	logLine("ไม่เจอที่ตำแหน่งที่บังคับไว้ จะไปค้นหาแทน")
	return ""
end lookInWorkFolder


on waitForNewTimeline(marker, outFolder, wantedName, maxTries)
	-- ค้นหาไฟล์ที่ Final Cut Pro เพิ่งเซฟ
	-- ส่งโฟลเดอร์ปลายทางเข้าไปด้วย เพราะห้องข่าวทำงานบนไดรฟ์เครือข่าย
	-- ซึ่งมักเป็นที่เดียวกับที่ Final Cut Pro จำไว้เป็นที่เซฟล่าสุด
	repeat with i from 1 to maxTries
		try
			set found to do shell script "/usr/bin/env python3 " & ¬
				quoted form of (resourcesPath & "/tools/find_recent.py") & ¬
				" " & quoted form of marker & ¬
				" " & quoted form of outFolder & ¬
				" " & quoted form of workPath & ¬
				" --name " & quoted form of wantedName
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


on waitForSheet(maxSeconds)
	-- คอยดูว่าหน้าต่างเซฟของ Final Cut Pro โผล่มาหรือยัง
	-- ตรวจทั้งแบบแผ่นซ้อนบนหน้าต่าง และแบบหน้าต่างแยก
	repeat with i from 1 to maxSeconds
		try
			tell application "System Events"
				tell process fcpName
					repeat with windowRef in windows
						if (count of sheets of windowRef) > 0 then return true
					end repeat
					-- บางรุ่นเปิดเป็นหน้าต่างแยก มีชื่อว่า Export XML
					repeat with windowRef in windows
						if name of windowRef contains "Export XML" then return true
					end repeat
				end tell
			end tell
		end try
		delay 1
	end repeat
	return false
end waitForSheet


on typeTextSafely(theText)
	-- ห้ามใช้ keystroke กับข้อความที่ไม่ใช่ภาษาอังกฤษเด็ดขาด
	--
	-- เหตุผล คำสั่ง keystroke จำลองการกดแป้นพิมพ์ตามผังแป้นที่ใช้อยู่
	-- ถ้าผังแป้นเป็นภาษาอังกฤษ พอสั่งพิมพ์คำว่า เช้า พ จะได้ aaaa a ออกมาแทน
	-- ซึ่งเคยทำให้ไฟล์ถูกตั้งชื่อผิดและเซฟผิดที่มาแล้ว
	--
	-- วิธีที่ถูกคือ ใส่ข้อความลงคลิปบอร์ด แล้วสั่งวาง
	-- การวางไม่ผ่านผังแป้นพิมพ์ ตัวอักษรจึงตรงทุกตัวไม่ว่าภาษาอะไร
	set the clipboard to theText
	delay 0.3
	tell application "System Events"
		tell process fcpName
			keystroke "a" using {command down}
			delay 0.2
			keystroke "v" using {command down}
			delay 0.4
		end tell
	end tell
end typeTextSafely


on goToFolderSafely(folderPath)
	-- พาหน้าต่างเซฟไปยังโฟลเดอร์ที่ต้องการ โดยใช้การวาง ไม่ใช่การพิมพ์
	tell application "System Events"
		tell process fcpName
			set frontmost to true
			keystroke "g" using {command down, shift down}
		end tell
	end tell
	delay 1
	typeTextSafely(folderPath)
	tell application "System Events"
		tell process fcpName
			key code 36
		end tell
	end tell
	delay 1.2
end goToFolderSafely


on nameAndSaveSheet(tempName)
	-- พิมพ์ชื่อไฟล์ชั่วคราวลงในหน้าต่างเซฟ แล้วกดเซฟ
	-- ไม่ไปยุ่งกับที่เก็บไฟล์เลย ปล่อยให้เซฟที่เดิมที่ Final Cut Pro จำไว้
	set didSetField to false
	-- วิธีที่หนึ่ง ใส่ค่าลงช่องชื่อโดยตรง แม่นยำที่สุด ไม่ต้องพึ่งการพิมพ์
	try
		tell application "System Events"
			tell process fcpName
				repeat with windowRef in windows
					repeat with sheetRef in sheets of windowRef
						try
							set value of text field 1 of sheetRef to tempName
							set didSetField to true
							exit repeat
						end try
					end repeat
					if didSetField then exit repeat
				end repeat
			end tell
		end tell
	end try
	if didSetField then logLine("ใส่ชื่อลงช่องได้โดยตรง")

	-- วิธีที่สอง ถ้าใส่ตรง ๆ ไม่ได้ ค่อยพิมพ์แทน
	if not didSetField then typeTextSafely(tempName)
	tell application "System Events"
		tell process fcpName
			set frontmost to true
			delay 0.3
			key code 36
		end tell
	end tell
	delay 1.5
	-- เผื่อยังมีหน้าต่างถามอะไรค้างอยู่ ให้ตอบให้จบ
	dismissLeftoverSheets()
end nameAndSaveSheet


on dismissLeftoverSheets()
	-- ตอบหน้าต่างที่ Final Cut Pro อาจเด้งขึ้นมาหลังกดเซฟ
	-- ที่พบบ่อยที่สุดคือ ถามว่าไฟล์ชื่อนี้มีอยู่แล้ว จะเขียนทับไหม
	-- ถ้าไม่ตอบ ทุกอย่างจะค้างอยู่ตรงนั้น
	repeat 3 times
		set didAnswer to false
		try
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					repeat with windowRef in windows
						repeat with sheetRef in sheets of windowRef
							repeat with buttonName in {"Replace", "แทนที่", "Save", "Export", "OK"}
								try
									click button buttonName of sheetRef
									set didAnswer to true
									exit repeat
								end try
							end repeat
							if didAnswer then exit repeat
						end repeat
						if didAnswer then exit repeat
					end repeat
				end tell
			end tell
		end try
		if not didAnswer then exit repeat
		logLine("ตอบหน้าต่างที่เด้งขึ้นมาแล้ว")
		delay 1
	end repeat
end dismissLeftoverSheets


-- ============================================================
-- นำงานย่อยกลับเข้า Final Cut Pro
-- ============================================================

on cleanUpTempTimeline(xmlPath)
	-- ลบเฉพาะไฟล์ชั่วคราวที่โปรแกรมสร้างเองเท่านั้น
	-- ตรวจชื่อก่อนเสมอ เพื่อไม่ให้เผลอไปลบไฟล์ของผู้ใช้
	try
		set fileName to do shell script "basename " & quoted form of xmlPath
		if fileName starts with "ghostexport-" then
			do shell script "rm -rf " & quoted form of xmlPath
			logLine("ลบไฟล์ไทม์ไลน์ชั่วคราวแล้ว " & xmlPath)
		else
			logLine("ไม่ลบ เพราะไม่ใช่ไฟล์ชั่วคราวของโปรแกรม " & fileName)
		end if
	on error e
		logLine("ลบไฟล์ชั่วคราวไม่สำเร็จ " & e)
	end try
end cleanUpTempTimeline


on importTimeline(splitPath)
	-- วิธีนี้เชื่อถือได้กว่าการกดเมนูมาก
	-- เพราะเป็นการบอก macOS ให้เปิดไฟล์ด้วย Final Cut Pro ตรง ๆ
	-- Final Cut Pro จะนำเข้าให้เองโดยไม่ต้องกดปุ่มอะไรเลย
	do shell script "open -a " & quoted form of "/Applications/Final Cut Pro.app" & " " & quoted form of splitPath
	delay 2

	-- ถ้ามีหน้าต่างถามเรื่องการนำเข้า ให้ตอบให้เอง
	set answered to clickButtonAnywhere({"Import", "OK", "นำเข้า"}, 5)
	if answered then
		logLine("ตอบหน้าต่างนำเข้าให้แล้ว")
	else
		logLine("ไม่มีหน้าต่างนำเข้าให้ตอบ")
	end if
	delay 2
end importTimeline


-- ============================================================
-- เอ็กพอร์ต พร้อมแสดงเปอร์เซ็นต์
-- ============================================================

on runExportStage(outFolder, namesFile, totalFiles)
	logLine("เริ่มขั้นเอ็กพอร์ต ต้องได้ " & totalFiles & " ไฟล์")
	shareWith("Export File", "ไฟล์ mov", outFolder)
	shareWith("MXF-50", "ไฟล์ mxf", outFolder)
	monitorProgress(outFolder, namesFile, totalFiles)
end runExportStage


on focusBrowser(strategyNumber)
	-- ย้ายโฟกัสไปที่ Browser ด้วยวิธีต่างกัน เผื่อวิธีหนึ่งไม่ได้ผล
	try
		if strategyNumber is 1 then
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					delay 0.4
					set windowMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "Window")
					set goToItem to (first menu item of windowMenu whose name starts with "Go To")
					click (first menu item of menu 1 of goToItem whose name starts with "Libraries")
				end tell
			end tell
		else if strategyNumber is 2 then
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					delay 0.3
					keystroke "1" using {command down}
				end tell
			end tell
		else
			-- วิธีสุดท้าย กดปุ่ม Escape เพื่อออกจากช่องกรอกใด ๆ ก่อน แล้วค่อยลองใหม่
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					key code 53
					delay 0.3
					keystroke "1" using {command down}
				end tell
			end tell
		end if
		delay 0.7
		return true
	on error
		return false
	end try
end focusBrowser


on selectAllInBrowser()
	try
		tell application "System Events"
			tell process fcpName
				set editMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "Edit")
				click (first menu item of editMenu whose name is "Select All")
			end tell
		end tell
		delay 0.6
		return true
	on error
		try
			tell application "System Events"
				tell process fcpName to keystroke "a" using {command down}
			end tell
			delay 0.6
			return true
		on error
			return false
		end try
	end try
end selectAllInBrowser


on openShareDestination(destinationName)
	try
		tell application "System Events"
			tell process fcpName
				set frontmost to true
				delay 0.3
				set fileMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "File")
				set shareItem to (first menu item of fileMenu whose name starts with "Share")
				click (first menu item of menu 1 of shareItem whose name starts with destinationName)
			end tell
		end tell
		return true
	on error e
		logLine("เปิดเมนู Share ไม่สำเร็จ " & e)
		return false
	end try
end openShareDestination


on shareWith(destinationName, humanName, outFolder)
	logLine("เริ่มสั่ง Share " & destinationName)

	-- ลองเลือกงานหลายวิธี แล้วพิสูจน์ทุกครั้งว่าเลือกครบจริง
	--
	-- วิธีพิสูจน์ ถ้าเลือกครบทุกอัน Final Cut Pro จะถามหาโฟลเดอร์อย่างเดียว
	-- แต่ถ้าเลือกได้อันเดียว มันจะมีช่องกรอกชื่อไฟล์โผล่มาด้วย
	-- จุดนี้คือสิ่งที่ทำให้เคยได้ไฟล์มาแค่ก้อนเดียว จึงต้องพิสูจน์ก่อนเซฟเสมอ
	set ready to false
	repeat with strategyNumber from 1 to 3
		if not focusBrowser(strategyNumber) then
			logLine("ย้ายโฟกัสวิธีที่ " & strategyNumber & " ไม่สำเร็จ")
		end if
		if not selectAllInBrowser() then
			logLine("สั่งเลือกทั้งหมดวิธีที่ " & strategyNumber & " ไม่สำเร็จ")
		end if

		if not openShareDestination(destinationName) then exit repeat
		delay 2
		if not clickButtonAnywhere({"Next…", "Next...", "Next"}, 8) then
			logLine("หาปุ่ม Next ไม่เจอ")
		end if
		delay 1.5

		set fieldCount to countSaveFields()
		logLine("วิธีที่ " & strategyNumber & " หน้าต่างเซฟมีช่องกรอก " & fieldCount & " ช่อง")
		if fieldCount is 0 then
			set ready to true
			exit repeat
		end if

		-- มีช่องกรอก แปลว่าเลือกได้อันเดียว ต้องถอยออกมาลองวิธีถัดไป
		logLine("เลือกไม่ครบ ถอยออกมาลองวิธีถัดไป")
		cancelEverything()
		delay 1
	end repeat

	if not ready then
		logLine("ลองครบทุกวิธีแล้วยังเลือกไม่ครบ")
		cancelEverything()
		display dialog ¬
			"เลือกงานย่อยให้ครบอัตโนมัติไม่สำเร็จ" & return & return & ¬
			"ถ้าปล่อยไปจะได้ไฟล์มาไม่ครบ" & return & return & ¬
			"ขอให้ไปที่ Final Cut Pro" & return & ¬
			"คลิกงานย่อยอันแรก กด Shift ค้าง แล้วคลิกอันสุดท้าย" & return & return & ¬
			"เลือกครบแล้วกดปุ่มข้างล่าง" ¬
			buttons {"เลือกครบแล้ว"} default button 1 with title appTitle
		if not openShareDestination(destinationName) then return
		delay 2
		clickButtonAnywhere({"Next…", "Next...", "Next"}, 8)
		delay 1.5
	end if

	-- ถึงตรงนี้แปลว่าอยู่ในหน้าต่างเลือกโฟลเดอร์แล้ว
	try
		goToFolderSafely(outFolder)
		logLine("พาไปโฟลเดอร์ปลายทางแล้ว")
	on error e
		logLine("พาไปโฟลเดอร์ไม่สำเร็จ " & e)
	end try

	set saved to clickButtonAnywhere({"Save", "Choose", "Open", "Export"}, 6)
	if not saved then
		try
			tell application "System Events" to tell process fcpName to key code 36
			set saved to true
		end try
	end if

	if saved then
		logLine("สั่งเอ็กพอร์ต " & destinationName & " เรียบร้อย")
		delay 1
		dismissLeftoverSheets()
	else
		logLine("กดยืนยันไม่สำเร็จ")
		display dialog ¬
			"เหลือขั้นสุดท้ายของ " & humanName & return & return & ¬
			"เลือกโฟลเดอร์นี้แล้วกดยืนยัน" & return & outFolder ¬
			buttons {"สั่งแล้ว"} default button 1 with title appTitle
	end if
end shareWith


on countSaveFields()
	-- นับช่องกรอกในหน้าต่างเซฟที่เปิดอยู่
	-- ใช้แยกว่าเป็นหน้าต่างเลือกโฟลเดอร์ หรือหน้าต่างตั้งชื่อไฟล์
	set total to 0
	try
		tell application "System Events"
			tell process fcpName
				repeat with windowRef in windows
					repeat with sheetRef in sheets of windowRef
						try
							set total to total + (count of text fields of sheetRef)
						end try
					end repeat
				end repeat
			end tell
		end tell
	end try
	return total
end countSaveFields


on clickButtonAnywhere(buttonNames, maxSeconds)
	-- หาปุ่มตามชื่อที่ให้มา ทั้งในหน้าต่างและในแผ่นซ้อน
	-- Final Cut Pro วางปุ่มไว้ไม่เหมือนกันในแต่ละหน้าต่าง จึงต้องกวาดหาให้ทั่ว
	repeat with i from 1 to maxSeconds
		try
			tell application "System Events"
				tell process fcpName
					repeat with windowRef in windows
						repeat with sheetRef in sheets of windowRef
							repeat with buttonName in buttonNames
								try
									click button buttonName of sheetRef
									return true
								end try
							end repeat
						end repeat
						repeat with buttonName in buttonNames
							try
								click button buttonName of windowRef
								return true
							end try
						end repeat
					end repeat
				end tell
			end tell
		end try
		delay 1
	end repeat
	return false
end clickButtonAnywhere


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
-- ทดสอบละเอียด
-- ------------------------------------------------------------
-- ตัวนี้มีไว้เพื่ออย่างเดียว คือเก็บของจริงจากเครื่องผู้ใช้
-- ว่าเมนูชื่ออะไรจริง ๆ ปุ่มชื่ออะไรจริง ๆ หน้าต่างมีอะไรบ้าง
--
-- เพราะผู้พัฒนาไม่มี Final Cut Pro จึงทดสอบเองไม่ได้
-- ที่ผ่านมาต้องเดาชื่อเมนูและชื่อปุ่ม ซึ่งเดาผิดหลายรอบ
-- ตัวนี้จะจบการเดา ด้วยการไปอ่านของจริงมาเลย
--
-- ปลอดภัย เพราะเปิดหน้าต่างขึ้นมาดูแล้วกดยกเลิกทุกครั้ง
-- ไม่มีการเซฟ ไม่มีการเอ็กพอร์ต ไม่แตะงานของผู้ใช้
-- ============================================================

on runDeepTest()
	if not ensureFinalCutRunning() then return
	if not ensureAccessibility() then return

	display dialog ¬
		"ตัวนี้จะไปอ่านชื่อเมนูและชื่อปุ่มจริงในเครื่องคุณ" & return & return & ¬
		"ไม่มีการเซฟ ไม่มีการเอ็กพอร์ต ไม่แตะงานของคุณ" & return & ¬
		"เปิดหน้าต่างขึ้นมาดูแล้วกดยกเลิกทุกครั้ง" & return & return & ¬
		"ใช้เวลาประมาณ 30 วินาที" & return & ¬
		"ระหว่างนี้อย่าแตะเมาส์และคีย์บอร์ด" ¬
		buttons {"เริ่มทดสอบ"} default button 1 with title appTitle

	set reportPath to workPath & "/ผลทดสอบละเอียด.txt"
	do shell script "rm -f " & quoted form of reportPath
	writeReport(reportPath, "===== ผลทดสอบละเอียด =====")
	writeReport(reportPath, "เวลา " & ((current date) as string))

	-- ข้อมูลเครื่อง เผื่อชื่อเมนูต่างกันตามรุ่น
	try
		writeReport(reportPath, "macOS " & (do shell script "sw_vers -productVersion"))
		writeReport(reportPath, "Final Cut Pro " & (do shell script "/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Applications/Final Cut Pro.app/Contents/Info.plist'"))
	end try

	-- ส่วนที่หนึ่ง รายชื่อเมนูจริง
	writeReport(reportPath, "")
	writeReport(reportPath, "--- เมนู File ทั้งหมด ---")
	writeReport(reportPath, listMenuItems("File"))

	writeReport(reportPath, "")
	writeReport(reportPath, "--- เมนูย่อยของ Share ---")
	writeReport(reportPath, listSubMenuItems("File", "Share"))

	writeReport(reportPath, "")
	writeReport(reportPath, "--- เมนูย่อยของ Window แล้ว Go To ---")
	writeReport(reportPath, listSubMenuItems("Window", "Go To"))

	writeReport(reportPath, "")
	writeReport(reportPath, "--- เมนู Edit ทั้งหมด ---")
	writeReport(reportPath, listMenuItems("Edit"))

	writeReport(reportPath, "")
	writeReport(reportPath, "--- สถานะเมนูที่โปรแกรมต้องใช้ ---")
	writeReport(reportPath, "Export XML = " & menuItemState("File", "Export XML"))
	writeReport(reportPath, "Share Export File = " & shareItemState("Export File"))
	writeReport(reportPath, "Share MXF-50 = " & shareItemState("MXF-50"))

	-- ส่วนที่สอง เปิดหน้าต่างเซฟขึ้นมาดูโครงสร้างจริง แล้วยกเลิก
	writeReport(reportPath, "")
	writeReport(reportPath, "--- หน้าต่าง Export XML มีอะไรบ้าง ---")
	try
		clickMenuItem("File", "Export XML")
		if waitForSheet(12) then
			writeReport(reportPath, describeWindows())
		else
			writeReport(reportPath, "หน้าต่างไม่โผล่ภายใน 12 วินาที")
		end if
	on error e
		writeReport(reportPath, "เปิดไม่สำเร็จ " & e)
	end try
	cancelEverything()

	-- ส่วนที่สาม เปิดหน้าต่าง Share ขึ้นมาดู แล้วยกเลิก
	writeReport(reportPath, "")
	writeReport(reportPath, "--- หน้าต่าง Share Export File มีอะไรบ้าง ---")
	try
		tell application "System Events"
			tell process fcpName
				set frontmost to true
				delay 0.4
				set fileMenu to menu 1 of (first menu bar item of menu bar 1 whose name is "File")
				set shareItem to (first menu item of fileMenu whose name starts with "Share")
				click (first menu item of menu 1 of shareItem whose name starts with "Export File")
			end tell
		end tell
		delay 4
		writeReport(reportPath, describeWindows())
	on error e
		writeReport(reportPath, "เปิดไม่สำเร็จ " & e)
	end try
	cancelEverything()

	writeReport(reportPath, "")
	writeReport(reportPath, "===== จบผลทดสอบ =====")

	do shell script "open -R " & quoted form of reportPath
	display dialog ¬
		"ทดสอบเสร็จแล้ว" & return & return & ¬
		"เปิด Finder ให้แล้ว ไฟล์ชื่อ ผลทดสอบละเอียด.txt" & return & return & ¬
		"ส่งไฟล์นี้กลับมาให้ผม" & return & ¬
		"ในนั้นมีชื่อเมนูและชื่อปุ่มจริงของเครื่องคุณครบทุกอัน" & return & ¬
		"ผมจะแก้ได้ตรงจุดในรอบเดียว ไม่ต้องเดาอีก" ¬
		buttons {"ปิด"} default button 1 with title appTitle
end runDeepTest


on writeReport(reportPath, theText)
	try
		do shell script "echo " & quoted form of theText & " >> " & quoted form of reportPath
	end try
end writeReport


on listMenuItems(menuName)
	try
		tell application "System Events"
			tell process fcpName
				set theNames to name of every menu item of menu 1 of ¬
					(first menu bar item of menu bar 1 whose name is menuName)
			end tell
		end tell
		return joinNames(theNames)
	on error e
		return "อ่านไม่ได้ " & e
	end try
end listMenuItems


on listSubMenuItems(menuName, parentPrefix)
	try
		tell application "System Events"
			tell process fcpName
				set parentMenu to menu 1 of (first menu bar item of menu bar 1 whose name is menuName)
				set parentItem to (first menu item of parentMenu whose name starts with parentPrefix)
				set theNames to name of every menu item of menu 1 of parentItem
			end tell
		end tell
		return joinNames(theNames)
	on error e
		return "อ่านไม่ได้ " & e
	end try
end listSubMenuItems


on joinNames(theNames)
	set output to ""
	repeat with aName in theNames
		if aName is not missing value then
			set output to output & "   [" & aName & "]" & return
		end if
	end repeat
	if output is "" then return "   ไม่มีรายการ"
	return output
end joinNames


on describeWindows()
	-- บอกว่าตอนนี้มีหน้าต่างอะไรอยู่ และในนั้นมีปุ่มกับช่องกรอกอะไรบ้าง
	set output to ""
	try
		tell application "System Events"
			tell process fcpName
				repeat with windowRef in windows
					set output to output & "หน้าต่าง [" & (name of windowRef) & "]" & return
					try
						set buttonNames to name of every button of windowRef
						set output to output & "   ปุ่ม " & my joinInline(buttonNames) & return
					end try
					try
						set fieldCount to count of text fields of windowRef
						set output to output & "   ช่องกรอก " & fieldCount & " ช่อง" & return
					end try
					repeat with sheetRef in sheets of windowRef
						set output to output & "   แผ่นซ้อนในหน้าต่างนี้" & return
						try
							set buttonNames to name of every button of sheetRef
							set output to output & "      ปุ่ม " & my joinInline(buttonNames) & return
						end try
						try
							set fieldCount to count of text fields of sheetRef
							set output to output & "      ช่องกรอก " & fieldCount & " ช่อง" & return
						end try
					end repeat
				end repeat
			end tell
		end tell
	on error e
		set output to output & "อ่านไม่ได้ " & e
	end try
	if output is "" then return "ไม่พบหน้าต่าง"
	return output
end describeWindows


on joinInline(theNames)
	set output to ""
	repeat with aName in theNames
		if aName is not missing value then set output to output & "[" & aName & "] "
	end repeat
	if output is "" then return "ไม่มีปุ่ม"
	return output
end joinInline


on cancelEverything()
	-- ปิดทุกหน้าต่างที่เปิดค้างไว้ ด้วยการกดยกเลิก
	-- ต้องแน่ใจว่าไม่มีอะไรค้าง เพราะนี่เป็นแค่การทดสอบ
	repeat 4 times
		set didCancel to false
		try
			tell application "System Events"
				tell process fcpName
					set frontmost to true
					repeat with windowRef in windows
						repeat with sheetRef in sheets of windowRef
							try
								click button "Cancel" of sheetRef
								set didCancel to true
							end try
						end repeat
						try
							click button "Cancel" of windowRef
							set didCancel to true
						end try
					end repeat
				end tell
			end tell
		end try
		if not didCancel then exit repeat
		delay 1
	end repeat
	-- กันเหนียว กดปุ่ม Escape อีกครั้ง
	try
		tell application "System Events" to tell process fcpName to key code 53
	end try
	delay 1
end cancelEverything


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


on runSplit(inputPath, gapSeconds, outputPath, eventName)
	return do shell script "/usr/bin/env python3 " & ¬
		quoted form of (resourcesPath & "/tools/fcpxml_split.py") & ¬
		" " & quoted form of inputPath & " --min-gap " & gapSeconds & ¬
		" --event-name " & quoted form of eventName & ¬
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
