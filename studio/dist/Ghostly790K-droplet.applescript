-- Ghostly790K AI Final Cut Studio — แอปตัดต่ออัตโนมัติ (ภาษาไทย)
-- ลากไฟล์วิดีโอ (mov/mp4) มาวางบนไอคอนแอปนี้ หรือดับเบิลคลิกเพื่อเลือกไฟล์
--   • 1 ไฟล์  → ตัดต่ออัตโนมัติตามคำสั่งภาษาไทย
--   • หลายไฟล์ → เลือกได้: ซิงก์มุมกล้อง (multicam) หรือตัดต่อทีละไฟล์
-- ได้ไฟล์ .fcpxml ที่เปิดใน Final Cut Pro ได้ทันที ฟุตเทจออนไลน์

property defaultCommand : "คัตเสียงคลิปนี้โดยเน้นประโยคสำคัญที่น่าสนใจ ความยาวเหลือไม่เกิน 3 นาที ใส่ซับไตเติ้ล"

on open theItems
	if (count of theItems) is 1 then
		processFiles(theItems)
	else
		set choice to button returned of (display dialog "ลากมา " & (count of theItems) & " ไฟล์ — ต้องการทำอะไร" buttons {"ยกเลิก", "ตัดต่อทีละไฟล์", "ซิงก์มุมกล้อง (multicam)"} default button "ซิงก์มุมกล้อง (multicam)" with title "Ghostly790K")
		if choice is "ซิงก์มุมกล้อง (multicam)" then
			syncMulticam(theItems)
		else if choice is "ตัดต่อทีละไฟล์" then
			processFiles(theItems)
		end if
	end if
end open

on run
	set theFile to choose file with prompt "เลือกไฟล์วิดีโอที่จะตัดต่อ (mov / mp4)"
	processFiles({theFile})
end run

-- โฟลเดอร์แพ็กเกจ (มี bin/ghostly, models/, logs/) + ปลดล็อกครั้งแรก
on packageDir()
	set appPath to POSIX path of (path to me)
	set pkgDir to do shell script "dirname " & quoted form of appPath
	do shell script "cd " & quoted form of pkgDir & " && xattr -dr com.apple.quarantine . 2>/dev/null; chmod +x bin/ghostly 2>/dev/null; mkdir -p logs; true"
	return pkgDir
end packageDir

-- คำสั่งเชลล์มาตรฐาน: กันเครื่องหลับ (caffeinate) + เก็บ log ไว้วิเคราะห์
on runGhostly(pkgDir, argsText)
	set logPath to pkgDir & "/logs/ghostly.log"
	set shellCmd to "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; cd " & quoted form of pkgDir & " && /usr/bin/caffeinate -im ./bin/ghostly " & argsText & " 2>>" & quoted form of logPath
	with timeout of 86400 seconds
		do shell script shellCmd
	end timeout
end runGhostly

on tailLog(pkgDir)
	try
		return do shell script "tail -6 " & quoted form of (pkgDir & "/logs/ghostly.log")
	on error
		return ""
	end try
end tailLog

-- ซับอัตโนมัติพร้อมไหม (มี whisper-cli + โมเดลใน models/)
on whisperReady(pkgDir)
	try
		do shell script "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; command -v whisper-cli >/dev/null && ls " & quoted form of pkgDir & "/models/*.bin >/dev/null 2>&1"
		return true
	on error
		return false
	end try
end whisperReady

on processFiles(theItems)
	set pkgDir to packageDir()

	-- ถ้าซับยังไม่พร้อม บอกตรง ๆ ก่อนเริ่ม ไม่ข้ามเงียบ ๆ
	set withSubs to whisperReady(pkgDir)
	if not withSubs then
		set subChoice to button returned of (display dialog "ยังไม่ได้ติดตั้งตัวถอดเสียงซับไทย (whisper)" & return & "คลิปจะถูกตัดต่อโดย 'ไม่มีซับไตเติ้ล'" & return & return & "ติดตั้งได้โดยรัน \"ติดตั้งครั้งแรก.command\" (คลิกขวา → Open) — จะติดตั้ง whisper และดาวน์โหลดโมเดลให้อัตโนมัติ" buttons {"ยกเลิก", "ดูวิธีติดตั้ง", "ตัดต่อโดยไม่มีซับ"} default button "ตัดต่อโดยไม่มีซับ" with title "Ghostly790K")
		if subChoice is "ยกเลิก" then return
		if subChoice is "ดูวิธีติดตั้ง" then
			do shell script "open " & quoted form of (pkgDir & "/อ่านก่อนใช้.txt")
			return
		end if
	end if

	set dialogResult to display dialog "คำสั่งตัดต่อ (พิมพ์ภาษาไทยได้เลย)" default answer defaultCommand buttons {"ยกเลิก", "เริ่มตัดต่อ"} default button "เริ่มตัดต่อ" with title "Ghostly790K"
	if button returned of dialogResult is "ยกเลิก" then return
	set editCommand to text returned of dialogResult
	if editCommand is "" then set editCommand to defaultCommand

	repeat with theItem in theItems
		set videoPath to POSIX path of theItem
		try
			display notification "ไฟล์ใหญ่อาจใช้เวลาหลายนาที อย่าเพิ่งปิดโปรแกรมนะครับ" with title "Ghostly790K" subtitle "กำลังตัดต่อ: " & videoPath
			set outPath to my fcpxmlPath(videoPath)
			set argsText to "auto " & quoted form of videoPath & " --command " & quoted form of editCommand & " --remember --out " & quoted form of outPath
			if withSubs then
				set modelPath to do shell script "ls " & quoted form of (pkgDir & "/models") & "/*.bin | head -1"
				set argsText to argsText & " --model " & quoted form of modelPath
			end if
			runGhostly(pkgDir, argsText)
			set userChoice to button returned of (display dialog "เสร็จแล้ว ✅" & return & outPath & return & return & "เปิดใน Final Cut Pro เลยไหม" buttons {"ไว้ก่อน", "เปิดเลย"} default button "เปิดเลย" with title "Ghostly790K")
			if userChoice is "เปิดเลย" then
				do shell script "open " & quoted form of outPath
			end if
		on error errorMessage
			display dialog "มีข้อผิดพลาดกับไฟล์:" & return & videoPath & return & return & errorMessage & return & return & tailLog(pkgDir) buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"
		end try
	end repeat
end processFiles

-- ซิงก์มุมกล้อง: ทุกไฟล์ที่ลากมา = คนละมุมของงานเดียวกัน
on syncMulticam(theItems)
	set pkgDir to packageDir()
	set fileArgs to ""
	repeat with theItem in theItems
		set fileArgs to fileArgs & " " & quoted form of (POSIX path of theItem)
	end repeat
	set firstPath to POSIX path of (item 1 of theItems)
	set parentDir to do shell script "dirname " & quoted form of firstPath
	set outPath to parentDir & "/มัลติแคม.fcpxml"
	try
		display notification "กำลังวิเคราะห์เสียงทุกมุมกล้อง อาจใช้เวลาหลายนาทีสำหรับไฟล์ใหญ่" with title "Ghostly790K" subtitle "ซิงก์มุมกล้อง"
		runGhostly(pkgDir, "sync" & fileArgs & " --out " & quoted form of outPath)
		set userChoice to button returned of (display dialog "ซิงก์มุมกล้องเสร็จแล้ว ✅" & return & outPath & return & return & "นำเข้า FCP แล้วจะได้ multicam clip พร้อมตัดสลับมุม — เปิดเลยไหม" buttons {"ไว้ก่อน", "เปิดเลย"} default button "เปิดเลย" with title "Ghostly790K")
		if userChoice is "เปิดเลย" then
			do shell script "open " & quoted form of outPath
		end if
	on error errorMessage
		display dialog "ซิงก์มุมกล้องไม่สำเร็จ:" & return & errorMessage & return & return & tailLog(pkgDir) buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"
	end try
end syncMulticam

-- "…/คลิป.mp4" → "…/คลิป.fcpxml" (ถ้าไม่มีนามสกุลก็ต่อท้ายตรง ๆ)
on fcpxmlPath(videoPath)
	set AppleScript's text item delimiters to "."
	set parts to text items of videoPath
	if (count of parts) > 1 then
		set base to (items 1 thru -2 of parts) as text
	else
		set base to videoPath
	end if
	set AppleScript's text item delimiters to ""
	return base & ".fcpxml"
end fcpxmlPath
