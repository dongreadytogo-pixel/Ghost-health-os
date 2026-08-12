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
global runLogPath
global watcherPath
global gapPath
global boardPath


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
	set runLogPath to workPath & "/กำลังทำงาน.txt"
	set watcherPath to workPath & "/แสดงความคืบหน้า.command"
	set gapPath to workPath & "/ค่าช่องว่าง.txt"
	set boardPath to workPath & "/สรุปสด.txt"
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
	--
	-- บันทึกลงไฟล์ แจ้งเตือนบนหน้าจอ และเขียนลงหน้าต่างความคืบหน้าด้วย
	--
	-- ข้อสุดท้ายสำคัญ ผู้ใช้ขอไว้ว่าทุกการทำงานต้องโชว์ว่าทำอะไรอยู่
	-- ขั้นตอนย่อยที่อยู่ลึก ๆ ก็ต้องขึ้นในหน้าต่างนั้นเหมือนกัน
	-- ไม่ใช่เฉพาะขั้นตอนใหญ่
	--
	-- logLine เขียนลงหน้าต่างความคืบหน้าให้แล้ว ตรงนี้จึงไม่ต้องเขียนซ้ำ
	logLine(stepText)
	try
		do shell script "echo " & quoted form of stepText & " > " & quoted form of statusPath
	end try
	try
		display notification stepText with title appTitle
	end try
end say


on logLine(theText)
	--
	-- เขียนลงทั้งไฟล์บันทึกถาวร และหน้าต่างความคืบหน้า
	--
	-- ทำไมต้องลงทั้งสองที่
	-- รอบที่แล้วหน้าต่างความคืบหน้าแสดงแต่ขั้นตอนใหญ่
	-- ส่วนบรรทัดที่บอกรายละเอียดจริง ๆ เช่น
	--   กดปุ่ม Next แล้ว
	--   หน้าต่างเซฟมีช่องกรอกกี่ช่อง
	--   ช่อง Roles as ตอนนี้โชว์ว่าอะไร
	-- ไปลงแต่ในไฟล์บันทึก ซึ่งไม่มีใครเห็นตอนนั้น
	--
	-- ผลคือพอมีปัญหา หน้าต่างกลับไม่มีข้อมูลที่ต้องใช้หาสาเหตุเลย
	-- ทั้งที่ผู้ใช้ขอไว้ว่าทุกการทำงานต้องโชว์ว่าทำอะไรอยู่
	--
	set stamp to "--:--:--"
	try
		set stamp to do shell script "date +%H:%M:%S"
	end try
	try
		do shell script "echo " & quoted form of ("[" & stamp & "] " & theText) & ¬
			" >> " & quoted form of logPath
	end try
	try
		do shell script "echo " & quoted form of ("[" & stamp & "]  " & theText) & ¬
			" >> " & quoted form of runLogPath
	end try
end logLine



-- ============================================================
-- หน้าต่างแสดงความคืบหน้า
-- ------------------------------------------------------------
-- ผู้ใช้ขอไว้ว่า กดปุ่มเดียวแล้วรันเองหมด และต้องเห็นตลอดว่าทำอะไรอยู่
-- คล้ายหน้าต่างของโปรแกรมดาวน์โหลด
--
-- ทำไมไม่ใช้กล่องข้อความแบบเดิม
-- กล่องข้อความของ macOS ขวางการทำงาน และแย่งโฟกัสจาก Final Cut Pro
-- ที่ผ่านมาจึงต้องตั้งให้มันหายไปเองทุกสี่วินาที ซึ่งกะพริบและอ่านยาก
--
-- วิธีที่ใช้แทน
-- โปรแกรมเขียนทุกขั้นตอนลงไฟล์ข้อความไฟล์หนึ่ง
-- แล้วเปิดหน้าต่างเล็ก ๆ ที่คอยอ่านไฟล์นั้นซ้ำทุกวินาที
-- หน้าต่างนั้นจึงอัปเดตตัวเองตลอดเวลา และไม่ขวางอะไรเลย
--
-- ใช้วิธีเปิดไฟล์คำสั่งด้วย open ไม่ได้สั่งงาน Terminal ตรง ๆ
-- จะได้ไม่ต้องขออนุญาตควบคุมโปรแกรมอื่นเพิ่มอีกตัว
-- ============================================================

on startProgressWindow(headline)
	--
	-- เริ่มไฟล์บันทึกของรอบนี้ใหม่ แล้วเปิดหน้าต่างที่คอยอ่านไฟล์นั้น
	--
	-- รุ่นก่อนสร้างไฟล์คำสั่งขึ้นมาสด ๆ ด้วยคำสั่งเขียนไฟล์ของ AppleScript
	-- ซึ่งเป็นส่วนที่เปราะ และผู้พัฒนาทดสอบล่วงหน้าไม่ได้เพราะไม่มีเครื่อง Mac
	-- ผลคือโปรแกรมเปิดไม่ขึ้นเลย และผู้ใช้ไม่เห็นสาเหตุอะไรทั้งสิ้น
	--
	-- รุ่นนี้ใช้ไฟล์สำเร็จรูปที่ทดสอบไว้แล้ว แล้วแค่คัดลอกออกมาเปิด
	-- ไม่มีการเขียนไฟล์ด้วย AppleScript อีกเลย
	--
	try
		do shell script "echo " & quoted form of headline & " > " & quoted form of runLogPath
	end try
	-- ล้างกระดานสรุปของรอบก่อนทิ้ง จะได้ไม่แสดงค่าค้างจากรอบที่แล้ว
	try
		do shell script "printf 'กำลังเริ่ม\n\n\n' > " & quoted form of boardPath
	end try

	try
		do shell script "cp " & quoted form of (resourcesPath & "/แสดงความคืบหน้า.command") & ¬
			" " & quoted form of watcherPath & " && chmod +x " & quoted form of watcherPath
		do shell script "open " & quoted form of watcherPath
	on error e
		logLine("เปิดหน้าต่างความคืบหน้าไม่สำเร็จ " & e)
	end try
end startProgressWindow


on showStep(stepText)
	--
	-- บอกหนึ่งขั้นตอนใหญ่ ลงหน้าต่างความคืบหน้าและไฟล์บันทึกถาวร
	--
	-- ต่างจาก say ตรงที่ไม่ส่งการแจ้งเตือนขึ้นมุมจอ
	-- เพราะขั้นตอนใหญ่มีหลายขั้น ถ้าเด้งทุกขั้นจะกวนเกินไป
	--
	logLine(stepText)
	setBoardStep(stepText)
end showStep


on setBoardStep(stepText)
	--
	-- เขียนบรรทัดแรกของกระดานสรุป คือขั้นตอนที่กำลังทำอยู่
	--
	-- กระดานสรุปคือสามบรรทัดที่หน้าต่างความคืบหน้าเอาไปแสดงตัวใหญ่ด้านบน
	-- อยู่ที่เดิมเสมอ ผู้ใช้จึงกวาดตาดูจุดเดียวก็รู้ว่าถึงไหนแล้ว
	-- ไม่ต้องไล่อ่านข้อความที่ไหลผ่านไปเรื่อย ๆ
	--
	try
		set barLine to ""
		set situationLine to ""
		try
			set barLine to do shell script "sed -n '2p' " & quoted form of boardPath
		end try
		try
			set situationLine to do shell script "sed -n '3p' " & quoted form of boardPath
		end try
		do shell script "printf '%s\n%s\n%s\n' " & ¬
			quoted form of stepText & " " & ¬
			quoted form of barLine & " " & ¬
			quoted form of situationLine & " > " & quoted form of boardPath
	end try
end setBoardStep


on setBoardProgress(barLine, situationLine)
	-- เขียนบรรทัดที่สองและสาม คือแถบความคืบหน้าและคำอธิบาย
	try
		set stepLine to ""
		try
			set stepLine to do shell script "sed -n '1p' " & quoted form of boardPath
		end try
		do shell script "printf '%s\n%s\n%s\n' " & ¬
			quoted form of stepLine & " " & ¬
			quoted form of barLine & " " & ¬
			quoted form of situationLine & " > " & quoted form of boardPath
	end try
end setBoardProgress


on stepBar(doneCount, totalCount, noteText)
	--
	-- ความคืบหน้าไปอยู่บนกระดานสรุป ไม่ไหลลงรายละเอียด
	--
	-- รุ่นก่อนเขียนบรรทัดนี้ต่อท้ายเรื่อย ๆ ทุกไม่กี่วินาที
	-- ผลคือรายละเอียดเต็มไปด้วยแถบความคืบหน้าซ้ำ ๆ จนกลบเรื่องอื่นหมด
	-- ตอนนี้มันทับที่เดิมบนกระดาน จึงเห็นค่าล่าสุดเสมอโดยไม่รก
	--
	set percent to 0
	if totalCount > 0 then set percent to round (doneCount * 100 / totalCount)
	my setBoardProgress(bar(percent) & "  " & percent & "%   ได้ " & doneCount & ¬
		" จาก " & totalCount & " ไฟล์", noteText)
end stepBar


on endProgressWindow(summaryText)
	-- ใส่คำว่าจบลงไป หน้าต่างที่คอยอ่านอยู่จะหยุดเองเมื่อเห็นบรรทัดนี้
	try
		do shell script "echo " & quoted form of ("" & return & summaryText & return & "@@จบ@@") & ¬
			" >> " & quoted form of runLogPath
	end try
end endProgressWindow


-- ============================================================
-- หน้าจอหลัก
-- ============================================================

on showMainMenu()
	repeat
		activate
		set choice to button returned of (display dialog ¬
			"เปิดงานข่าวใน Final Cut Pro" & return & ¬
			"แล้วคลิกที่ชื่องานนั้นหนึ่งครั้ง" & return & return & ¬
			"จากนั้นกด RUN แล้วเลือกโฟลเดอร์ปลายทาง" & return & return & ¬
			"หลังจากนั้นไม่ต้องกดอะไรอีกเลย" & return & ¬
			"โปรแกรมจะแยกก้อน สั่งเอ็กพอร์ต และเก็บไฟล์ให้เอง" & return & ¬
			"พร้อมเปิดหน้าต่างบอกทุกขั้นตอนที่กำลังทำอยู่" ¬
			buttons {"ปิดโปรแกรม", "เมนูอื่น", "RUN"} ¬
			default button "RUN" with title appTitle)

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
	-- เมนูนี้เคยยาวถึงเก้าหัวข้อ ซึ่งมากเกินไปสำหรับการใช้งานจริง
	-- ผู้ใช้บอกตรง ๆ ว่าควรกดปุ่มเดียวแล้วจบ ไม่ใช่มานั่งเลือกเมนู
	--
	-- เหลือสามปุ่มที่ใช้จริง ที่เหลือยุบไปไว้ในเครื่องมือช่าง
	--
	repeat
		activate
		set choice to button returned of (display dialog ¬
			"เมนูเพิ่มเติม" & return & return & ¬
			"เปลี่ยนโฟลเดอร์  ตอนนี้เก็บไฟล์ไว้ที่" & return & ¬
			"                " & currentOutputFolder() & return & return & ¬
			"ดูบันทึก        ไฟล์บอกว่าโปรแกรมทำอะไรไปบ้าง" ¬
			buttons {"เครื่องมือช่าง", "เปลี่ยนโฟลเดอร์", "ดูบันทึก"} ¬
			default button "ดูบันทึก" with title appTitle)
		if choice is "ดูบันทึก" then
			showLog()
			return
		else if choice is "เปลี่ยนโฟลเดอร์" then
			chooseOutputFolder()
			return
		else
			showToolMenu()
		end if
	end repeat
end showOtherMenu


on currentOutputFolder()
	-- โฟลเดอร์ปลายทางที่จำไว้ เอาไว้โชว์ในเมนูให้เห็นว่าตอนนี้เก็บที่ไหน
	try
		set saved to do shell script "cat " & quoted form of prefsPath
		if saved is not "" then return saved
	end try
	return "ยังไม่ได้เลือก"
end currentOutputFolder


on showToolMenu()
	--
	-- เครื่องมือสำหรับหาสาเหตุเวลามีปัญหา ไม่ใช่ของที่ต้องใช้ทุกวัน
	--
	repeat
		set menuItems to {¬
			"เก็บไฟล์ที่ตกค้าง  ใช้เมื่อรอบก่อนหยุดกลางคัน", ¬
			"ทดสอบเลือก preset  ดูว่าโปรแกรมเลือก 3 Stereo ได้ไหม", ¬
			"ตรวจ preset  อ่านไฟล์ 3 Stereo ในเครื่องว่าถูกต้องไหม", ¬
			"เก็บไฟล์ตั้งค่ามาให้ผม  รวมไฟล์ตั้งค่าไว้บนหน้าจอ", ¬
			"ดูค่าที่ตั้งไว้  อ่านค่า Roles ที่เครื่องนี้บันทึกไว้ในไฟล์", ¬
			"จำค่านี้ไว้  ถ่ายสำเนาค่าที่ตั้งถูกแล้ว เก็บไว้ใช้ทีหลัง", ¬
			"ใส่ค่าที่จำไว้กลับ  ใช้เมื่อค่า Roles เปลี่ยนไปเอง", ¬
			"ตรวจเสียง  เกณฑ์จำนวน Role ขั้นต่ำ ตอนนี้ " & requiredChannels() & "  ศูนย์คือไม่ตรวจ", ¬
			"ปรับจำนวนก้อน  ค่าช่องว่างตอนนี้ " & savedGapSeconds() & " วินาที"}
		activate
		set picked to (choose from list menuItems ¬
			with title appTitle ¬
			with prompt ("เครื่องมือช่าง" & return & "ใช้ตอนหาสาเหตุเท่านั้น") ¬
			OK button name "ตกลง" cancel button name "กลับ" ¬
			without multiple selections allowed and empty selection allowed)
		if picked is false then return

		set choice to item 1 of picked
		if choice starts with "เก็บไฟล์ที่ตกค้าง" then
			collectLeftovers()
		else if choice starts with "ทดสอบเลือก preset" then
			runBuildRolesLayout()
		else if choice starts with "ตรวจ preset" then
			checkRolePreset()
		else if choice starts with "เก็บไฟล์ตั้งค่ามาให้ผม" then
			collectSettingFiles()
		else if choice starts with "ดูค่าที่ตั้งไว้" then
			reportRolesSettings()
		else if choice starts with "จำค่านี้ไว้" then
			rememberRolesSettings()
		else if choice starts with "ใส่ค่าที่จำไว้กลับ" then
			restoreRolesSettings()
		else if choice starts with "ตรวจเสียง" then
			askRequiredChannels()
		else
			changeGapSeconds()
		end if
	end repeat
end showToolMenu


on changeGapSeconds()
	--
	-- ปรับว่าช่องว่างกี่วินาทีจึงนับเป็นก้อนใหม่
	--
	-- เดิมโปรแกรมถามทุกรอบก่อนเอ็กพอร์ต ซึ่งขัดกับการกดปุ่มเดียวแล้วจบ
	-- ย้ายมาไว้ตรงนี้ ตั้งครั้งเดียวแล้วจำไว้ให้เลย
	--
	set currentValue to savedGapSeconds()
	set answer to askGapSeconds(currentValue)
	if answer is "" then return
	do shell script "echo " & quoted form of answer & " > " & quoted form of gapPath
	logLine("ตั้งค่าช่องว่างเป็น " & answer & " วินาที")
	activate
	display dialog "บันทึกแล้ว ใช้ค่าช่องว่าง " & answer & " วินาที" ¬
		buttons {"ตกลง"} default button "ตกลง" with title appTitle
end changeGapSeconds


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


on checkRolePreset()
	--
	-- ตรวจไฟล์ preset ชื่อ 3 Stereo ที่เก็บอยู่ในเครื่อง
	--
	-- ผู้ใช้ส่งไฟล์ 3 Stereo.rolepreset มาให้ดู ทำให้เรารู้โครงสร้างจริงแล้ว
	-- ข้างในบอกครบว่าต้องมีสามแทร็กเสียง แทร็กละสองช่อง
	-- และแต่ละแทร็กรับ All Music กับ All Dialogue กับ All Effects
	--
	-- การอ่านไฟล์แน่นอนกว่าการอ่านหน้าจอมาก
	-- เพราะไม่ขึ้นกับว่าหน้าต่างเปิดอยู่ไหม หรือชื่อหน้าต่างเป็นอะไร
	--
	set reportPath to workPath & "/ตรวจ preset.txt"
	set outcome to ""
	try
		set outcome to do shell script "/usr/bin/env python3 " & ¬
			quoted form of (resourcesPath & "/tools/roles_presets.py") & ¬
			" check " & quoted form of "3 Stereo" & " 2>&1 || true"
	on error e
		logLine("ตรวจ preset ไม่สำเร็จ " & e)
		activate
		display dialog "ตรวจ preset ไม่สำเร็จ" & return & return & e ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle
		return
	end try

	logLine("ผลตรวจ preset" & return & outcome)
	try
		do shell script "echo " & quoted form of outcome & " > " & quoted form of reportPath
	end try

	if outcome contains "ไม่พบ preset" then
		-- ไม่มี preset ในเครื่อง เสนอให้ติดตั้งของสำรองที่ติดมากับโปรแกรม
		activate
		set answer to button returned of (display dialog ¬
			"ไม่พบ preset ชื่อ 3 Stereo ในเครื่องนี้" & return & return & ¬
			"โปรแกรมมีสำเนาของไฟล์นี้ติดมาด้วย" & return & ¬
			"จะให้ติดตั้งคืนให้ไหม" & return & return & ¬
			"ต้องปิด Final Cut Pro ก่อน แล้วเปิดใหม่หลังติดตั้ง" ¬
			buttons {"ไม่ต้อง", "ติดตั้งให้เลย"} ¬
			default button "ติดตั้งให้เลย" with title appTitle with icon caution)
		if answer is "ติดตั้งให้เลย" then installRolePreset()
		return
	end if

	activate
	if outcome contains "ตรงกับที่ห้องข่าวต้องการ" then
		display dialog ¬
			"preset ถูกต้องครบทุกข้อ" & return & return & outcome ¬
			buttons {"ดี"} default button "ดี" with title appTitle
	else
		putOnDesktop(reportPath, "ตรวจ preset.txt")
		display dialog ¬
			"preset ยังไม่ตรงกับที่ต้องการ" & return & return & outcome & return & return & ¬
			"วางไฟล์ผลตรวจไว้บนหน้าจอแล้ว" ¬
			buttons {"ปิด"} default button "ปิด" with title appTitle with icon caution
	end if
end checkRolePreset


on installRolePreset()
	-- เอาสำเนา preset ที่ติดมากับโปรแกรม ใส่กลับเข้าเครื่อง
	set sourceFile to resourcesPath & "/presets/3 Stereo.rolepreset"
	try
		set outcome to do shell script "/usr/bin/env python3 " & ¬
			quoted form of (resourcesPath & "/tools/roles_presets.py") & ¬
			" install " & quoted form of sourceFile & " 2>&1"
		logLine("ติดตั้ง preset " & outcome)
		activate
		display dialog "ติดตั้ง preset เรียบร้อย" & return & return & outcome & return & return & ¬
			"เปิด Final Cut Pro ขึ้นมาใหม่ได้เลย" ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle
	on error e
		logLine("ติดตั้ง preset ไม่สำเร็จ " & e)
		activate
		display dialog "ติดตั้ง preset ไม่สำเร็จ" & return & return & e ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle with icon caution
	end try
end installRolePreset


on collectSettingFiles()
	--
	-- ไปเก็บไฟล์ตั้งค่าทุกไฟล์มาวางไว้บนหน้าจอ
	--
	-- ทำไมต้องมีปุ่มนี้
	-- ไฟล์พวกนี้อยู่ในโฟลเดอร์ที่ macOS ซ่อนเอาไว้
	-- บอกทางให้ผู้ใช้เดินไปเองก็ได้ แต่ผิดพลาดง่ายและเสียเวลา
	-- ให้โปรแกรมไปเก็บมาให้เลยดีกว่า จบในปุ่มเดียว
	--
	-- เก็บสองอย่าง
	--   rolepreset  คือ preset ของ Roles เช่นไฟล์ 3 Stereo
	--   fcpdest     คือไฟล์ของปลายทาง เช่น MXF-50
	--
	-- รอบแรกเก็บเฉพาะสองนามสกุลนี้ ผลคือได้มาไฟล์เดียว
	-- ไฟล์ของปลายทางไม่เจอเลย แปลว่าการเดานามสกุลของผมผิด
	-- เมื่อเดาไม่ถูก ก็ไม่ต้องเดา รุ่นนี้เก็บมาทั้งโฟลเดอร์เลย
	-- โฟลเดอร์ตั้งค่าพวกนี้เล็กมาก เก็บหมดก็ไม่หนัก และได้เห็นของจริงครบ
	--
	-- คัดลอกอย่างเดียว ไม่ย้ายและไม่ลบของเดิม
	--
	set folderName to "ไฟล์ตั้งค่า Final Cut " & (do shell script "date +%d-%m-%H%M")
	set targetFolder to (do shell script "echo $HOME") & "/Desktop/" & folderName

	set copiedCount to ""
	try
		set copiedCount to do shell script "/usr/bin/env python3 " & ¬
			quoted form of (resourcesPath & "/tools/roles_presets.py") & ¬
			" collectall " & quoted form of targetFolder
	on error e
		logLine("เก็บไฟล์ตั้งค่าไม่สำเร็จ " & e)
		activate
		display dialog ¬
			"ไม่พบไฟล์ตั้งค่าในเครื่องนี้" & return & return & ¬
			"ลองอีกทางหนึ่ง" & return & ¬
			"เปิดหน้าต่าง MXF-50 กดที่ช่อง Roles as" & return & ¬
			"แล้วเลือก Reveal User Presets in Finder" ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle with icon caution
		return
	end try

	logLine("เก็บไฟล์ตั้งค่าได้ " & copiedCount & " ไฟล์ ไว้ที่ " & targetFolder)
	try
		do shell script "open " & quoted form of targetFolder
	end try
	activate
	display dialog ¬
		"เก็บไฟล์ตั้งค่ามาให้แล้ว " & copiedCount & " ไฟล์" & return & return & ¬
		"อยู่บนหน้าจอ ในโฟลเดอร์ชื่อ" & return & folderName & return & return & ¬
		"ลากทั้งโฟลเดอร์ไปวางในช่องแชทได้เลย" & return & ¬
		"หรือจะเปิดเข้าไปแล้วลากทีละไฟล์ก็ได้" & return & return & ¬
		"ของเดิมในเครื่องไม่ถูกแตะ เป็นการคัดลอกอย่างเดียว" ¬
		buttons {"ตกลง"} default button "ตกลง" with title appTitle
end collectSettingFiles


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


on rolesPresetIsSet(wantedSetting)
	--
	-- ดูว่าช่อง Roles as ตอนนี้เป็นค่าที่ต้องการแล้วหรือยัง
	--
	-- ช่องนั้นไม่มีชื่อให้จับ แต่มันโชว์ค่าปัจจุบันของตัวเองอยู่
	-- เราจึงมองหาข้อความนั้นในหน้าต่างแทน ถ้าเจอ แปลว่าถูกตั้งไว้แล้ว
	--
	-- รุ่นก่อนอ่านค่าด้วยการเรียกหน้าต่างจากชื่อ ซึ่งบันทึกพิสูจน์แล้วว่าพัง
	-- จึงรายงานว่าไม่สำเร็จทุกครั้ง ทั้งที่ผู้ใช้ตั้งถูกแล้ว
	--
	set windowIndex to my findShareWindow()
	if windowIndex is 0 then return false
	return (count of my collectAt(windowIndex, {wantedSetting}, true)) > 0
end rolesPresetIsSet


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
	-- ใช้โฟลเดอร์เดิมเหมือนตอนเอ็กพอร์ต จะได้ไม่ต้องเลือกซ้ำ
	set outFolder to outputFolder()
	if outFolder is "" then return
	monitorAndCollect(outFolder, namesFile, totalFiles)
end collectLeftovers


-- ============================================================
-- ลำดับการทำงาน
-- ============================================================

on runWorkflow()
	--
	-- กดปุ่มเดียวแล้วรันเองจนจบ
	--
	-- ผู้ใช้ขอไว้ชัดว่า หลังเลือกโฟลเดอร์แล้ว ไม่ต้องถามอะไรอีกเลย
	-- รุ่นก่อนมีหน้าต่างให้กดยืนยันถึงสามจุดระหว่างทาง
	-- ซึ่งขัดกับจุดประสงค์ของโปรแกรม คือให้คนไม่ต้องมานั่งเฝ้า
	--
	-- ทุกจุดที่เคยถาม เปลี่ยนเป็นเขียนบอกในหน้าต่างความคืบหน้าแทน
	-- ถ้าจำนวนก้อนไม่ถูก ผู้ใช้เห็นได้ทันทีในหน้าต่างนั้น
	-- แล้วค่อยไปปรับค่าช่องว่างใน เครื่องมือช่าง แล้วสั่งใหม่
	--
	try
		if not ensureFinalCutRunning() then return
		if not ensureAccessibility() then return

		set outFolder to outputFolder()
		if outFolder is "" then return

		startProgressWindow("แยกงานข่าว  กำลังทำงาน" & return & ¬
			"ปล่อยไว้ได้เลย ไม่ต้องกดอะไรอีก" & return & ¬
			"หน้าต่างนี้จะบอกทุกขั้นตอนเอง" & return & ¬
			"----------------------------------------")

		showStep("โฟลเดอร์ปลายทาง " & outFolder)

		showStep("ขั้นที่ 1  ขอไทม์ไลน์จาก Final Cut Pro")
		set xmlPath to fetchTimeline(outFolder)
		if xmlPath is "" then
			endProgressWindow("หยุดแล้ว ไม่ได้ไทม์ไลน์มา")
			return
		end if

		set gapSeconds to savedGapSeconds()
		showStep("ขั้นที่ 2  แยกก้อน ใช้ค่าช่องว่าง " & gapSeconds & " วินาที")
		showStep(runBrief(xmlPath, gapSeconds))

		set splitPath to (workPath & "/แยกแล้ว.fcpxml")
		set eventName to "แยกงาน " & (do shell script "date +%d-%m' '%H%M")
		runSplit(xmlPath, gapSeconds, splitPath, eventName)

		set namesFile to workPath & "/รายชื่อไฟล์.txt"
		do shell script "/usr/bin/env python3 " & quoted form of (resourcesPath & "/tools/fcpxml_segments.py") & ¬
			" " & quoted form of xmlPath & " --min-gap " & gapSeconds & " --names > " & quoted form of namesFile
		set totalFiles to (do shell script "grep -c . " & quoted form of namesFile) as integer
		showStep("แยกเสร็จ ต้องได้ทั้งหมด " & totalFiles & " ไฟล์")

		showStep("ขั้นที่ 3  ตรวจเสียงของแต่ละก้อน")
		checkAudioBeforeExport(xmlPath, gapSeconds)

		showStep("ขั้นที่ 4  นำงานย่อยกลับเข้า Final Cut Pro")
		importTimeline(splitPath)

		-- ไม่ไปยุ่งกับการเลือกงานเลย
		--
		-- Final Cut Pro เลือกงานที่เพิ่งนำเข้าให้ทั้งหมดอยู่แล้ว
		-- ที่ผ่านมาโปรแกรมไปสั่งเลือกใหม่ ซึ่งอาจไปล้างการเลือกที่ถูกต้องทิ้ง
		-- แล้วเหลือแค่ชิ้นเดียว จึงได้ไฟล์มาก้อนเดียว
		--
		-- สั่ง Share สองรอบติดกันเลย ไม่ต้องรอไฟล์รอบแรกเสร็จ
		-- เพราะ Final Cut Pro รับงานเข้าคิวแล้วทยอยทำเองพร้อมกันได้
		-- จับเวลาไว้ด้วย รอบที่แล้วขั้นนี้ใช้เวลานานผิดปกติ
		-- มีตัวเลขกำกับ จะได้รู้ทันทีว่าแก้แล้วเร็วขึ้นจริงไหม
		set startedAt to (current date)
		showStep("ขั้นที่ 5  สั่งสร้างไฟล์ mov ทุกก้อนพร้อมกัน")
		shareTo("Export File", "ไฟล์ mov", "")
		showStep("ขั้นที่ 5 ใช้เวลา " & ((current date) - startedAt) & " วินาที")

		set startedAt to (current date)
		showStep("ขั้นที่ 6  สั่งสร้างไฟล์ mxf ทุกก้อนพร้อมกัน")
		shareTo("MXF-50", "ไฟล์ mxf", "3 Stereo")
		showStep("ขั้นที่ 6 ใช้เวลา " & ((current date) - startedAt) & " วินาที")

		showStep("ขั้นที่ 7  เฝ้าดูและเก็บไฟล์เข้าโฟลเดอร์ปลายทาง")
		monitorAndCollect(outFolder, namesFile, totalFiles)

	on error errorMessage number errorNumber
		if errorNumber is -128 then
			endProgressWindow("ผู้ใช้ยกเลิก")
			return
		end if
		logLine("พังกลางทาง " & errorMessage)
		showStep("เกิดปัญหา " & errorMessage)
		endProgressWindow("หยุดกลางทาง ไฟล์ที่ได้มาแล้วยังอยู่ครบ")
		activate
		display dialog ¬
			"เกิดปัญหา" & return & return & errorMessage & return & return & ¬
			"ไฟล์ที่เอ็กพอร์ตไปแล้วยังอยู่ครบ ไม่หายไปไหน" & return & return & ¬
			"กดปุ่ม เมนูอื่น แล้วเลือก เก็บไฟล์ที่ตกค้าง" & return & ¬
			"โปรแกรมจะไปตามเก็บมาให้" ¬
			buttons {"ปิด"} default button 1 with title appTitle with icon caution
	end try
end runWorkflow


on savedGapSeconds()
	-- ค่าช่องว่างที่ใช้แยกก้อน จำไว้ในไฟล์ จะได้ไม่ต้องถามทุกรอบ
	try
		set saved to do shell script "cat " & quoted form of gapPath
		if saved is not "" then return saved
	end try
	return "0.2"
end savedGapSeconds


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
	--
	-- จำนวน Role ของเสียงขั้นต่ำที่แต่ละก้อนต้องมี
	--
	-- ค่าเริ่มต้นคือ 0 แปลว่าไม่กำหนดจำนวน
	--
	-- เดิมผมตั้งไว้ที่ 6 ซึ่งมาจากที่ผมเข้าใจผิดว่าไฟล์ต้องมีหกแทร็กแยกกัน
	-- ความจริงคือสามแทร็กสเตอริโอ ที่แต่ละแทร็กรับ
	-- All Dialogue กับ All Effects กับ All Music
	-- ไทม์ไลน์จริงจึงมี Role ไม่ถึงหกตัว ทุกก้อนเลยถูกเตือนหมดทุกวัน
	--
	-- การเตือนที่ขึ้นทุกก้อนทุกครั้ง ไม่มีประโยชน์ มีแต่ทำให้เสียเวลา
	-- เกณฑ์จำนวนจึงปิดไว้เป็นค่าเริ่มต้น
	-- แต่ยังตรวจเรื่องที่มีประโยชน์จริงอยู่ คือก้อนไหนเสียงไม่เหมือนก้อนอื่น
	--
	try
		set saved to do shell script "cat " & quoted form of channelsPath
		if saved is not "" then return saved
	end try
	return "0"
end requiredChannels


on askRequiredChannels()
	-- ให้ผู้ใช้ตั้งเองว่าไฟล์ MXF ต้องมีกี่ช่องเสียง
	-- ห้องข่าวนี้ใช้หกช่องแยกกัน แต่ทำเป็นค่าตั้งไว้ เผื่องานอื่นใช้ไม่เท่ากัน
	activate
	try
		set answer to text returned of (display dialog ¬
			"แต่ละก้อนต้องมีเสียงอย่างน้อยกี่ Role" & return & return & ¬
			"ใส่ 0 แปลว่าไม่ตรวจจำนวน ซึ่งเป็นค่าเริ่มต้น" & return & return & ¬
			"ถึงใส่ 0 โปรแกรมก็ยังตรวจเรื่องที่สำคัญกว่าอยู่" & return & ¬
			"คือก้อนไหนมีเสียงไม่เหมือนก้อนอื่น ซึ่งมักแปลว่าลืมใส่เสียง" ¬
			default answer requiredChannels() ¬
			buttons {"ยกเลิก", "บันทึก"} default button "บันทึก" with title appTitle)
	on error number -128
		return
	end try

	set cleaned to do shell script "echo " & quoted form of answer & " | tr -cd '0-9'"
	if cleaned is "" then
		activate
		display dialog "ต้องเป็นตัวเลข" ¬
			buttons {"ตกลง"} default button "ตกลง" with title appTitle
		return
	end if

	do shell script "echo " & quoted form of cleaned & " > " & quoted form of channelsPath
	logLine("ตั้งจำนวน Role ของเสียงเป็น " & cleaned)
	activate
	set savedNote to "บันทึกแล้ว แต่ละก้อนต้องมีเสียงอย่างน้อย " & cleaned & " Role"
	if cleaned is "0" then set savedNote to "บันทึกแล้ว ปิดการตรวจจำนวน Role แล้ว"
	display dialog savedNote ¬
		buttons {"ตกลง"} default button "ตกลง" with title appTitle
end askRequiredChannels


on checkAudioBeforeExport(xmlPath, gapSeconds)
	--
	-- ตรวจเสียงแล้วรายงานอย่างเดียว ไม่หยุดงาน
	--
	-- ผู้ใช้ขอให้กดปุ่มเดียวแล้วรันเองจนจบ
	-- การเปิดหน้าต่างถามกลางทางจึงขัดกับสิ่งที่ขอ
	-- ผลตรวจจะไปโผล่ในหน้าต่างความคืบหน้าแทน อ่านได้ตลอดเวลา
	--
	set wanted to requiredChannels()
	set requireArgument to ""
	if wanted is not "0" then set requireArgument to " --require " & wanted
	set reportPath to workPath & "/ตรวจเสียง.txt"
	set summary to ""

	try
		-- ต่อท้ายด้วย true เพราะโปรแกรมตรวจจะคืนรหัส 1 เมื่อเจอก้อนที่เสียงไม่ครบ
		-- ซึ่งไม่ใช่ความผิดพลาด แต่เป็นผลการตรวจที่เราต้องการอ่าน
		set summary to do shell script "/usr/bin/env python3 " & ¬
			quoted form of (resourcesPath & "/tools/audio_audit.py") & " " & ¬
			quoted form of xmlPath & " --min-gap " & gapSeconds & ¬
			requireArgument & " --brief 2>&1 || true"
		do shell script "/usr/bin/env python3 " & ¬
			quoted form of (resourcesPath & "/tools/audio_audit.py") & " " & ¬
			quoted form of xmlPath & " --min-gap " & gapSeconds & ¬
			requireArgument & " > " & quoted form of reportPath & " 2>&1 || true"
	on error e
		showStep("ตรวจเสียงไม่สำเร็จ " & e)
		return true
	end try

	if summary starts with "เสียงครบ" then
		showStep(summary)
		return true
	end if

	-- เสียงไม่เหมือนกันทุกก้อน บอกไว้ให้เห็น แล้วทำงานต่อ
	-- พร้อมวางไฟล์รายละเอียดไว้บนหน้าจอ เผื่ออยากดูทีหลัง
	showStep("ระวัง  " & summary)
	showStep("รายละเอียดอยู่บนหน้าจอแล้ว ชื่อ ตรวจเสียง.txt")
	putOnDesktop(reportPath, "ตรวจเสียง.txt")
	return true
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


on outputFolder()
	--
	-- ใช้โฟลเดอร์เดิมทันที ไม่ต้องเลือกใหม่ทุกครั้ง
	--
	-- ผู้ใช้บอกไว้ชัดว่า มีหน้าที่แค่เลือกโฟลเดอร์ปลายทางเพียงครั้งเดียว
	-- ไม่ต้องคลิกอย่างอื่นอีกเลย
	--
	-- ครั้งแรกจึงถาม ครั้งต่อไปใช้ของเดิมเงียบ ๆ
	-- ถ้าโฟลเดอร์เดิมหายไป เช่นถอดไดรฟ์ออก จะถามใหม่ให้เอง
	-- เปลี่ยนเองได้ที่ เมนูอื่น แล้ว เปลี่ยนโฟลเดอร์ปลายทาง
	--
	set lastFolder to ""
	try
		set lastFolder to do shell script "cat " & quoted form of prefsPath
	end try
	if lastFolder is not "" then
		try
			do shell script "test -d " & quoted form of lastFolder
			return lastFolder
		on error
			logLine("โฟลเดอร์เดิมหายไปแล้ว " & lastFolder & " จะถามใหม่")
		end try
	end if
	return chooseOutputFolder()
end outputFolder


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

on markersInside(elementRef)
	--
	-- ของชิ้นนี้ หรือของที่อยู่ใต้มันสองชั้น มีปุ่มที่เป็นตัวชี้ไหม
	-- แยกออกมาเป็นฟังก์ชันเดี่ยว เพื่อให้เรียกใช้กับแผ่นซ้อนก็ได้ กับหน้าต่างก็ได้
	--
	set marker to false
	try
		tell application "System Events"
			repeat with a in UI elements of elementRef
				if my matchesAny(a, shareMarkers, true) then
					set marker to true
					exit repeat
				end if
				repeat with b in UI elements of a
					if my matchesAny(b, shareMarkers, true) then
						set marker to true
						exit repeat
					end if
				end repeat
				if marker then exit repeat
			end repeat
		end tell
	end try
	return marker
end markersInside


on windowHasMarker(windowIndex)
	--
	-- หน้าต่างนี้ใช่หน้าต่างของ Share ไหม ดูจากปุ่มที่มีเฉพาะในหน้าต่างนั้น
	--
	-- บทเรียนจากบันทึกจริง อ่านให้ดีก่อนแก้ตรงนี้
	--
	-- รุ่น 10.3 ค้นสามชั้น หาเจอ แต่ช้ามาก
	-- รุ่น 10.4 ผมลดเหลือสองชั้นเพื่อให้เร็ว ผลคือหาไม่เจอเลย
	--   บันทึกขึ้นว่า ไม่เจอหน้าต่างของ MXF-50 จึงสร้างแทร็กเสียงไม่ได้
	--   และยิ่งช้ากว่าเดิม เพราะวนหาจนครบสิบห้ารอบแล้วก็ไม่เจอ
	--   ขั้นที่ 5 ใช้ 31 วินาที ขั้นที่ 6 ใช้ 52 วินาที
	--
	-- สาเหตุที่แท้จริง หน้าต่างของ Share เป็นแผ่นซ้อนบนหน้าต่างหลัก
	-- ของที่เราหาจึงอยู่ลึกลงไปอีกหนึ่งชั้น คือ หน้าต่าง แล้วแผ่นซ้อน แล้วปุ่ม
	-- สองชั้นจึงไปไม่ถึง
	--
	-- ทางออกที่ทั้งเร็วและถูก ดูที่แผ่นซ้อนก่อนโดยตรง
	-- ไม่ต้องไล่ของทุกชิ้นในหน้าต่างหลักซึ่งมีเป็นพันชิ้น
	--
	set marker to false
	try
		with timeout of 8 seconds
			tell application "System Events"
				tell process fcpName
					-- แผ่นซ้อนก่อน เพราะเป็นที่ที่หน้าต่าง Share อยู่จริงบ่อยที่สุด
					if (exists sheet 1 of window windowIndex) then
						if my markersInside(sheet 1 of window windowIndex) then
							return true
						end if
					end if
					set marker to my markersInside(window windowIndex)
				end tell
			end tell
		end timeout
	end try
	return marker
end windowHasMarker


on shareSheetOf(windowIndex)
	--
	-- คืนค่าตัวแผ่นซ้อน ถ้าหน้าต่าง Share เป็นแผ่นซ้อน
	-- ถ้าไม่ใช่ ก็คืนตัวหน้าต่างเอง
	--
	-- ส่วนที่ไปหาปุ่มต่าง ๆ จะได้เริ่มจากจุดที่ถูกต้อง
	-- ไม่ต้องเผื่อความลึกเพิ่มอีกชั้นทุกที่
	--
	try
		with timeout of 8 seconds
			tell application "System Events"
				tell process fcpName
					if (exists sheet 1 of window windowIndex) then
						if my markersInside(sheet 1 of window windowIndex) then
							return sheet 1 of window windowIndex
						end if
					end if
					return window windowIndex
				end tell
			end tell
		end timeout
	on error
		return missing value
	end try
end shareSheetOf


on findShareWindow()
	--
	-- คืนค่าเป็นลำดับที่ของหน้าต่าง Share หรือ 0 ถ้าไม่เจอ
	--
	-- ดูหน้าต่างที่หนึ่งก่อนเสมอ
	-- หน้าต่างของ Share เป็นหน้าต่างที่เพิ่งเปิดและอยู่หน้าสุด
	-- หรือไม่ก็เป็นแผ่นซ้อนบนหน้าต่างหลัก ซึ่งก็คือหน้าต่างที่หนึ่งอยู่ดี
	--
	if my windowHasMarker(1) then return 1

	set foundIndex to 0
	try
		with timeout of 10 seconds
			tell application "System Events"
				tell process fcpName
					set howMany to count of windows
				end tell
			end tell
		end timeout
		repeat with i from 2 to howMany
			if my windowHasMarker(i) then
				set foundIndex to i
				exit repeat
			end if
		end repeat
	on error errorText
		logLine("หาหน้าต่าง Share ไม่สำเร็จ " & errorText)
	end try
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
	-- เริ่มค้นจากแผ่นซ้อนถ้ามี ไม่ใช่จากตัวหน้าต่าง
	-- เพราะหน้าต่าง Share มักเป็นแผ่นซ้อนบนหน้าต่างหลัก
	-- ถ้าเริ่มจากหน้าต่าง จะต้องเผื่อความลึกเพิ่มอีกหนึ่งชั้นทุกที่
	-- และต้องไล่ของในหน้าต่างหลักซึ่งมีเป็นพันชิ้น ทั้งช้าและไม่จำเป็น
	--
	set found to {}
	if windowIndex is 0 then return {}
	set searchRoot to my shareSheetOf(windowIndex)
	if searchRoot is missing value then return {}
	try
		with timeout of 30 seconds
			tell application "System Events"
				repeat with a in UI elements of searchRoot
					if my matchesAny(a, wantedList, mustBeExact) then set end of found to (contents of a)
					repeat with b in UI elements of a
						if my matchesAny(b, wantedList, mustBeExact) then set end of found to (contents of b)
						repeat with c in UI elements of b
							if my matchesAny(c, wantedList, mustBeExact) then set end of found to (contents of c)
							repeat with d in UI elements of c
								if my matchesAny(d, wantedList, mustBeExact) then set end of found to (contents of d)
								repeat with f in UI elements of d
									if my matchesAny(f, wantedList, mustBeExact) then set end of found to (contents of f)
								end repeat
							end repeat
						end repeat
					end repeat
				end repeat
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

	-- จดรายการทั้งหมดไว้เสมอ เผื่อชื่อจริงไม่ตรงกับที่คิด จะได้เห็นของจริง
	logLine("ในเมนูมี " & (itemNames as string))

	--
	-- หาชื่อที่จะกด
	--
	-- ลองแบบตรงเป๊ะก่อน ถ้าไม่เจอค่อยลองแบบมีคำนั้นอยู่ข้างใน
	-- เพราะรายการที่เป็น preset ที่ผู้ใช้บันทึกเอง
	-- บางทีมีช่องว่างหรือเครื่องหมายนำหน้า ทำให้ไม่ตรงเป๊ะ
	--
	set targetName to ""
	if itemNames contains itemName then
		set targetName to itemName
	else
		repeat with candidate in itemNames
			set candidateText to candidate as string
			if candidateText contains itemName then
				set targetName to candidateText
				logLine("เจอรายการที่ใกล้เคียง " & candidateText)
				exit repeat
			end if
		end repeat
	end if

	if targetName is "" then
		logLine("ในเมนูไม่มี " & itemName)
		my pressEscape()
		return false
	end if

	try
		with timeout of uiTimeout seconds
			tell application "System Events" to click menu item targetName of menu 1 of elementRef
		end timeout
		delay 0.7
		logLine("เลือก " & targetName & " แล้ว")
		return true
	on error errorText
		logLine("เลือก " & targetName & " ไม่สำเร็จ " & errorText)
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


-- ============================================================
-- เลือก preset ในช่อง Roles as
-- ------------------------------------------------------------
-- ทำไมรุ่นก่อน ๆ เลือกไม่ได้เลยสักครั้ง มีเหตุผลชัดเจนสองข้อ
--
-- ข้อแรก ช่องนั้นไม่มีชื่อให้จับ
-- ปุ่มอื่นในหน้าต่างมีชื่อเป็นตัวหนังสือ เช่น Add Audio Track หรือ Next
-- แต่ช่อง Roles as ไม่มี มันมีแต่ค่าที่ตัวเองโชว์อยู่
-- การค้นหาด้วยชื่อจึงไม่มีทางเจอ ต่อให้ค้นลึกกี่ชั้นก็ตาม
--
-- ข้อสอง วิธีที่ผมใช้แยกแยะว่าอันไหนคือช่องนั้น ใช้ไม่ได้
-- ผมเคยไล่ดูของทุกชิ้นแล้วถามว่า ในเมนูของแกมี 3 Stereo ไหม
-- ตั้งใจว่าจะได้ไม่ต้องกดมั่วไปโดนปุ่มอื่น
-- แต่บันทึกของผู้ใช้พิสูจน์แล้วว่า เมนูยังไม่ถูกสร้างจนกว่าจะกด
-- คำถามนั้นจึงได้คำตอบว่าไม่มี จากของทุกชิ้นในหน้าต่าง รวมทั้งช่องที่ใช่ด้วย
--
-- วิธีใหม่ ใช้ค่าที่ช่องนั้นโชว์อยู่เป็นตัวชี้
-- ช่อง Roles as โชว์ค่าปัจจุบันของตัวเองเสมอ และค่านั้นเป็นหนึ่งในชุดที่รู้จัก
-- เจอชิ้นที่โชว์ค่าเหล่านั้น ก็คือเจอช่องที่ถูกต้อง แล้วค่อยกดเปิดเมนู
-- ============================================================

on knownRolesValues()
	--
	-- ค่าที่เคยเห็นจริงในช่อง Roles as ของเครื่องนี้
	--
	-- 3 Stereo            มาจากภาพหน้าจอที่ผู้ใช้ส่งมา
	-- Multitrack MXF File  มาจากภาพหน้าจออีกใบของผู้ใช้
	-- ที่เหลือเป็นตัวเลือกมาตรฐานที่มีอยู่ในเมนูเดียวกัน
	--
	return {"3 Stereo", "Multitrack MXF File", "Multitrack QuickTime Movie", "Single Track"}
end knownRolesValues


on selectRolesPreset(wantedSetting)
	-- หาหน้าต่างเองเพียงครั้งเดียว เพราะถูกเรียกครั้งเดียวต่อหนึ่งรอบ
	set windowIndex to my findShareWindow()
	if windowIndex is 0 then return false

	--
	-- หาแบบขึ้นต้นด้วย ไม่ใช่ตรงเป๊ะ
	--
	-- ภาพหน้าจอของผู้ใช้แสดงว่าช่องนี้เขียนว่า
	--   Multitrack MXF File (edited)
	-- มีคำว่า edited ต่อท้ายด้วย เพราะมีการแก้จากค่าเดิม
	--
	-- รุ่นก่อนหาแบบตรงเป๊ะ จึงไม่เจอช่องนี้เลย ทั้งที่มันอยู่ตรงหน้า
	-- นี่คือสาเหตุที่พลาดอีกครั้ง ไม่ใช่เพราะหาไม่เจอ แต่เพราะเทียบผิดวิธี
	--
	set candidates to my collectAt(windowIndex, my knownRolesValues(), false)
	if (count of candidates) is 0 then
		logLine("ไม่เจอช่อง Roles as จากค่าที่มันโชว์อยู่")
		return false
	end if

	set theBox to item 1 of candidates
	if my labelOf(theBox) starts with wantedSetting then
		logLine("ช่อง Roles as เป็น " & my labelOf(theBox) & " อยู่แล้ว")
		return true
	end if

	logLine("ช่อง Roles as ตอนนี้โชว์ว่า " & my labelOf(theBox) & " กำลังเปลี่ยนเป็น " & wantedSetting)
	return my openMenuAndPick(theBox, wantedSetting)
end selectRolesPreset


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

	--
	-- ใช้ลำดับหน้าต่างเดิมต่อไปเลย ไม่ต้องหาใหม่
	--
	-- การกดแท็บ Roles ไม่ได้เปลี่ยนว่าหน้าต่างไหนเป็นหน้าต่างที่เท่าไร
	-- การหาใหม่ทุกครั้งจึงเสียเวลาเปล่า ซึ่งรวมกันแล้วเป็นนาที
	--

	--
	-- ลองเลือก preset ที่ผู้ใช้ตั้งไว้ก่อนเป็นอันดับแรก
	--
	-- นี่คือทางที่ควรจะเป็นตั้งแต่แรก กดครั้งเดียวได้ครบทั้งสามแทร็ก
	-- ที่ผ่านมาทำไม่ได้ เพราะวิธีค้นหาช่องนั้นของผมผิด ไม่ใช่เพราะเลือกไม่ได้
	-- รุ่นนี้ค้นหาจากค่าที่ช่องนั้นโชว์อยู่ ซึ่งเป็นวิธีที่ตรงกับความจริง
	--
	if my selectRolesPreset("3 Stereo") then
		delay 1.5
		set afterPreset to my countAudioTracksAt(windowIndex)
		set nowShows to my rolesPresetIsSet("3 Stereo")
		logLine("หลังเลือก preset ช่องโชว์ 3 Stereo ไหม " & nowShows & ¬
			"  ได้แทร็กเสียง " & afterPreset & " แทร็ก")
		-- ยืนยันสองทาง ทั้งค่าที่ช่องโชว์ และจำนวนแทร็กที่นับได้
		-- ทางใดทางหนึ่งผ่านก็พอ เพราะการนับแทร็กอาจอ่านไม่ได้ในบางจังหวะ
		if afterPreset ≥ 3 or nowShows then
			say("เลือก preset 3 Stereo สำเร็จ")
			return true
		end if
	end if

	--
	-- เลือก preset ไม่ได้
	--
	-- ผู้ใช้สั่งไว้ชัดว่า ต้องเลือกในช่องนั้น ไม่ใช่กด Add เพิ่มเอง
	-- รุ่นนี้จึงไม่กด Add ให้อัตโนมัติอีกแล้ว
	-- ถ้ามีแทร็กครบสามอยู่แล้วก็ผ่าน ถ้าไม่ครบก็บอกตรง ๆ ว่าไม่สำเร็จ
	--
	set trackCount to my countAudioTracksAt(windowIndex)
	logLine("เลือก preset ไม่สำเร็จ ตอนนี้มีแทร็กเสียงอยู่ " & trackCount & " แทร็ก")

	if trackCount ≥ 3 then
		say("มีแทร็กเสียงครบสามแทร็กแล้ว")
		return true
	end if

	dumpWindowTree(destinationName)
	return false
end buildRolesLayout


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
		repeat with waited from 1 to 10
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
			set rolesStartedAt to (current date)
			buildRolesLayout(destinationName)
			logLine("ขั้นตั้งเสียงใช้เวลา " & ((current date) - rolesStartedAt) & " วินาที")
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
	--
	-- เฝ้าดูไฟล์ที่ Final Cut Pro ทยอยสร้าง แล้วเก็บเข้าโฟลเดอร์ปลายทาง
	--
	-- รุ่นก่อนเปิดกล่องข้อความค้างไว้ แล้วให้มันหายเองทุกสี่วินาที
	-- ผลคือหน้าจอกะพริบ และแย่งโฟกัสจาก Final Cut Pro เป็นระยะ
	-- รุ่นนี้เขียนลงหน้าต่างความคืบหน้าแทน ไม่ขวางอะไรเลย
	--
	-- หยุดเองเมื่อได้ไฟล์ครบ หรือเมื่อเงียบนานเกินไปจนแน่ใจว่าจบแล้ว
	--
	set finished to false
	set lastDone to -1
	set quietRounds to 0
	set roundNumber to 0

	repeat
		set roundNumber to roundNumber + 1

		--
		-- ตามเก็บไฟล์ที่เขียนเสร็จแล้ว มาไว้ในโฟลเดอร์ปลายทาง
		--
		-- ตัวเก็บไฟล์บอกกลับมาสามตัวเลข
		--   บรรทัดที่ 1  ย้ายมาแล้วกี่ไฟล์ในรอบนี้
		--   บรรทัดที่ 2  เจอแล้วแต่ยังเขียนไม่เสร็จกี่ไฟล์
		--   บรรทัดที่ 3  ยังไม่เจอเลยกี่ไฟล์
		--
		-- ตัวเลขที่ 2 สำคัญมากสำหรับผู้ใช้
		-- มันคือคำตอบของคำถามว่า Final Cut Pro ทำงานอยู่จริงไหม
		-- รอบก่อนหน้าต่างขึ้นแค่ 0% ค้างอยู่ ทั้งที่เครื่องกำลังเรนเดอร์อยู่
		-- ผู้ใช้จึงเข้าใจว่าโปรแกรมค้าง ทั้งที่มันกำลังทำงานตามปกติ
		--
		set writingCount to 0
		set unseenCount to totalFiles
		try
			set threeNumbers to paragraphs of (do shell script "/usr/bin/env python3 " & ¬
				quoted form of (resourcesPath & "/tools/collect_outputs.py") & ¬
				" " & quoted form of outFolder & " " & quoted form of namesFile & ¬
				" --settle 2")
			if (count of threeNumbers) ≥ 3 then
				set writingCount to (item 2 of threeNumbers) as integer
				set unseenCount to (item 3 of threeNumbers) as integer
			end if
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

		-- อธิบายให้เห็นภาพว่าตอนนี้เกิดอะไรขึ้นบ้าง
		set situation to ""
		if writingCount > 0 then
			set situation to "Final Cut Pro กำลังเขียนอยู่ " & writingCount & " ไฟล์"
		else if unseenCount ≥ totalFiles then
			set situation to "ยังไม่เห็นไฟล์ไหนเลย Final Cut Pro น่าจะกำลังเรนเดอร์"
		else
			set situation to "รอไฟล์ที่เหลืออีก " & unseenCount & " ไฟล์"
		end if

		--
		-- ถือว่ามีความคืบหน้า เมื่อได้ไฟล์เพิ่ม หรือเมื่อยังมีไฟล์กำลังถูกเขียนอยู่
		--
		-- ข้อหลังสำคัญมาก ไฟล์ MXF ของข่าวสามนาทีใช้เวลาเขียนนาน
		-- ถ้านับว่าเงียบทั้งที่เครื่องกำลังเขียนอยู่ โปรแกรมจะเลิกรอกลางคัน
		-- แล้วสรุปว่าไม่สำเร็จ ทั้งที่อีกครู่เดียวไฟล์ก็จะเสร็จ
		--
		if doneCount > lastDone or writingCount > 0 then
			set quietRounds to 0
			set lastDone to doneCount
			my stepBar(doneCount, totalFiles, situation)
		else
			set quietRounds to quietRounds + 1
			-- บอกทุกสิบรอบพอ ไม่ให้หน้าต่างยาวเกินจนอ่านไม่ทัน
			if quietRounds mod 10 is 0 then
				my stepBar(doneCount, totalFiles, situation & ¬
					"   ผ่านไป " & (quietRounds * 4) & " วินาที")
			end if
		end if

		--
		-- เลิกรอเองเมื่อเงียบนานพอ
		--
		-- สองร้อยยี่สิบห้ารอบคือประมาณสิบห้านาทีที่เงียบสนิท
		-- คำว่าเงียบสนิทตรงนี้แปลว่า ไม่มีไฟล์ใหม่ และไม่มีไฟล์ไหนกำลังถูกเขียนด้วย
		-- ถ้าเครื่องยังเขียนอยู่ จะรอต่อไปเรื่อย ๆ ไม่นับเวลานี้
		-- รุ่นก่อนต้องให้คนมากดหยุดเอง ซึ่งขัดกับการรันเองจนจบ
		--
		if quietRounds > 225 then exit repeat
		delay 4
	end repeat

	if finished then
		showStep("ครบทุกไฟล์แล้ว " & totalFiles & " ไฟล์")
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
		showStep("หยุดรอแล้ว ยังขาดไฟล์อยู่")
		showStep("ไฟล์ที่ยังขาด" & return & missingList)

		--
		-- สำรวจว่า Final Cut Pro สร้างไฟล์อะไรออกมาบ้าง โดยไม่สนใจชื่อ
		--
		-- ตอบคำถามสำคัญที่สุดเวลาได้ศูนย์ไฟล์
		--   ถ้าเจอไฟล์ใหม่  เครื่องทำงานจริง แต่ชื่อหรือที่อยู่ไม่ตรงที่เราคาด
		--   ถ้าไม่เจอเลย    คำสั่งเอ็กพอร์ตไม่ได้ถูกส่งไปจริง
		-- สองอย่างนี้แก้คนละแบบ เดาจากข้างนอกไม่ได้ ต้องดูของจริง
		--
		showStep("กำลังสำรวจว่า Final Cut Pro สร้างไฟล์อะไรออกมาบ้าง")
		try
			set surveyText to do shell script "/usr/bin/env python3 " & ¬
				quoted form of (resourcesPath & "/tools/collect_outputs.py") & ¬
				" " & quoted form of outFolder & " " & quoted form of namesFile & ¬
				" --survey 90"
			showStep(surveyText)
		on error e
			showStep("สำรวจไม่สำเร็จ " & e)
		end try
		set headline to "ยังได้ไม่ครบ" & return & return & ¬
			"ไฟล์ที่ยังขาด" & return & missingList & return & return & ¬
			"ใช้ เมนูอื่น แล้ว เก็บไฟล์ที่ตกค้าง เพื่อตามเก็บอีกรอบ"
	end if

	endProgressWindow(headline & return & return & "ไฟล์อยู่ที่ " & outFolder)

	--
	-- เปิดโฟลเดอร์ปลายทางให้เลย แล้วแจ้งเตือนแบบไม่ขวาง
	--
	-- ผู้ใช้ขอไว้ว่าไม่ต้องคลิกอะไรอีกเลยหลังเลือกโฟลเดอร์
	-- กล่องสรุปเดิมค้างรอให้กด ซึ่งขัดกับข้อนั้น
	-- ถ้าเดินออกไปทำอย่างอื่น กลับมาก็เจอกล่องค้างอยู่ ไม่มีประโยชน์
	--
	-- รุ่นนี้เปิดโฟลเดอร์ให้ดูผลเลย และกล่องสรุปหายเองใน 30 วินาที
	--
	try
		do shell script "open " & quoted form of outFolder
	end try
	try
		display notification headline with title appTitle sound name "Glass"
	end try
	activate
	try
		display dialog headline & return & return & "ไฟล์อยู่ที่" & return & outFolder ¬
			buttons {"ปิด"} default button "ปิด" with title appTitle ¬
			giving up after 30
	end try
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
