-- Ghostly790K AI Final Cut Studio — เมนูคำสั่งภาษาไทย (วนใช้ซ้ำได้เรื่อย ๆ)
-- เปิดแอป = เมนูปุ่มเลือกคำสั่ง | ลากไฟล์มาวาง = ใช้ไฟล์นั้นกับเมนูทันที
-- ทุกงานให้ .fcpxml ที่เปิดใน Final Cut Pro ได้ทันที ฟุตเทจออนไลน์

property menuSmart : "✂️ คัตเสียงอัจฉริยะ — เน้นประโยคสำคัญ ≤ 3 นาที + ซับ"
property menuTikTok : "🎬 ทำคลิป TikTok — ตัดช่วงเงียบ + ซับ"
property menuYouTube : "📺 ตัดต่อแบบ YouTube — ตัดช่วงเงียบ + คำบรรยาย"
property menuClean : "🔇 ลดเสียงรบกวน + ตัดช่วงเงียบ + ซับ"
property menuTitleSubs : "🧢 ซับแบบ Title — แต่งใน FCP ได้เต็มที่"
property menuMulticam : "🎥 ซิงก์มุมกล้อง (multicam) — เลือกหลายไฟล์"
property menuCover : "🌟 SUBTITLE Cover — ไฮไลต์ป๊อบอัพขาว/ส้มจากซับเดิม"
property menuCustom : "✍️ พิมพ์คำสั่งเอง (ภาษาไทย)"
property menuQuit : "❌ ปิดโปรแกรม"

on run
	menuLoop({})
end run

on open theItems
	menuLoop(theItems)
end open

-- เมนูหลัก: เลือกคำสั่ง → ทำงาน → กลับมาที่เมนู จนกว่าจะกดปิด
-- สำคัญ: ห้ามรันคำสั่งเชลล์ใด ๆ ก่อนเมนูขึ้น — TCC ของ macOS อาจเด้งขอสิทธิ์
-- อยู่หลังหน้าต่างจนดูเหมือนแอปค้าง (เม้าส์หมุน) ตอนเปิดโปรแกรม
on menuLoop(droppedItems)
	set pkgDir to packageDir()
	repeat
		activate
		set actions to {menuSmart, menuTikTok, menuYouTube, menuClean, menuTitleSubs, ¬
			menuMulticam, menuCover, menuCustom, menuQuit}
		set picked to choose from list actions with prompt ¬
			"เลือกคำสั่ง (ทำเสร็จแล้วจะกลับมาที่เมนูนี้ ใช้ซ้ำได้เรื่อย ๆ)" ¬
			default items {menuSmart} with title "Ghostly790K — AI Final Cut Studio"
		if picked is false then return
		set action to item 1 of picked
		if action is menuQuit then return

		try
			if action is menuMulticam then
				doMulticam(pkgDir, droppedItems)
			else if action is menuCover then
				doCover(pkgDir)
			else
				set editCommand to commandFor(action)
				if editCommand is "" then
					set dlg to display dialog "พิมพ์คำสั่งตัดต่อ (ภาษาไทยได้เลย)" default answer ¬
						"คัตเสียงคลิปนี้โดยเน้นประโยคสำคัญที่น่าสนใจ ความยาวเหลือไม่เกิน 3 นาที ใส่ซับไตเติ้ล" ¬
						buttons {"ยกเลิก", "ตกลง"} default button "ตกลง" with title "Ghostly790K"
					if button returned of dlg is "ยกเลิก" then set editCommand to "-"
					if editCommand is not "-" then set editCommand to text returned of dlg
				end if
				if editCommand is not "-" and editCommand is not "" then
					doAutoEdit(pkgDir, droppedItems, editCommand)
				end if
			end if
		on error errorMessage number errorNumber
			if errorNumber is not -128 then
				display dialog "มีข้อผิดพลาด:" & return & errorMessage & return & return & ¬
					tailLog(pkgDir) buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"
			end if
		end try
		set droppedItems to {}   -- ไฟล์ที่ลากมาใช้กับรอบแรกเท่านั้น รอบต่อไปเลือกใหม่
	end repeat
end menuLoop

on commandFor(action)
	if action is menuSmart then return "คัตเสียงคลิปนี้โดยเน้นประโยคสำคัญที่น่าสนใจ ความยาวเหลือไม่เกิน 3 นาที ใส่ซับไตเติ้ล"
	if action is menuTikTok then return "ทำเป็นติ๊กต๊อก ตัดช่วงเงียบออก ใส่ซับ"
	if action is menuYouTube then return "ทำเป็นคลิปยูทูบ ตัดช่วงเงียบออก ใส่คำบรรยาย"
	if action is menuClean then return "ลดเสียงรบกวน ตัดช่วงเงียบออก ใส่ซับ"
	if action is menuTitleSubs then return "ตัดช่วงเงียบออก ใส่ซับแบบ Title"
	return ""   -- พิมพ์เอง
end commandFor

-- ตัดต่ออัตโนมัติ: ใช้ไฟล์ที่ลากมา หรือให้เลือก (เลือกหลายไฟล์ได้ ทำทีละไฟล์)
on doAutoEdit(pkgDir, droppedItems, editCommand)
	set theItems to droppedItems
	if (count of theItems) is 0 then
		set theItems to choose file with prompt "เลือกไฟล์วิดีโอ (mov / mp4) — เลือกหลายไฟล์ได้" ¬
			with multiple selections allowed
	end if

	-- ซับพร้อมไหม บอกตรง ๆ ก่อนเริ่ม — และติดตั้งให้เลยได้จากปุ่มเดียว
	set withSubs to whisperReady(pkgDir)
	if not withSubs then
		set subChoice to button returned of (display dialog ¬
			"ยังไม่ได้ติดตั้งตัวถอดเสียงซับไทย (whisper)" & return & return & ¬
			"กด \"ติดตั้งซับให้เลย\" — โปรแกรมจะติดตั้ง whisper และดาวน์โหลดโมเดล (~550MB) ให้อัตโนมัติ ใช้เวลา 5-15 นาที ครั้งเดียวจบ แล้วซับจะขึ้นทุกงานหลังจากนี้" ¬
			buttons {"ตัดต่อโดยไม่มีซับ", "ยกเลิก", "ติดตั้งซับให้เลย"} default button "ติดตั้งซับให้เลย" with title "Ghostly790K")
		if subChoice is "ยกเลิก" then return
		if subChoice is "ติดตั้งซับให้เลย" then
			installWhisper(pkgDir)
			set withSubs to whisperReady(pkgDir)
			if not withSubs then
				display dialog "ยังติดตั้งไม่สำเร็จ — จะตัดต่อโดยไม่มีซับไปก่อนนะครับ (รายละเอียดอยู่ใน logs/ghostly.log)" ¬
					buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"
			end if
		end if
	end if

	repeat with theItem in theItems
		set videoPath to POSIX path of theItem
		display notification "ไฟล์ใหญ่อาจใช้เวลาหลายนาที อย่าเพิ่งปิดโปรแกรม" with title "Ghostly790K" subtitle "กำลังตัดต่อ: " & videoPath
		set outPath to my fcpxmlPath(videoPath)
		set argsText to "auto " & quoted form of videoPath & " --command " & quoted form of editCommand & " --remember --out " & quoted form of outPath
		if withSubs then
			set modelPath to do shell script "ls " & quoted form of (pkgDir & "/models") & "/*.bin | head -1"
			set argsText to argsText & " --model " & quoted form of modelPath
		end if
		runGhostly(pkgDir, argsText)
		set userChoice to button returned of (display dialog "เสร็จแล้ว ✅" & return & outPath & return & return & ¬
			"เปิดใน Final Cut Pro เลยไหม" buttons {"ไว้ก่อน", "เปิดเลย"} default button "เปิดเลย" with title "Ghostly790K")
		if userChoice is "เปิดเลย" then do shell script "open " & quoted form of outPath
	end repeat
end doAutoEdit

-- ซิงก์มุมกล้อง: ทุกไฟล์ = คนละมุมของงานเดียวกัน
on doMulticam(pkgDir, droppedItems)
	set theItems to droppedItems
	if (count of theItems) < 2 then
		set theItems to choose file with prompt "เลือกวิดีโอทุกมุมกล้อง (กด Cmd ค้างเพื่อเลือกหลายไฟล์)" ¬
			with multiple selections allowed
	end if
	if (count of theItems) < 2 then
		display dialog "ซิงก์มุมกล้องต้องเลือกอย่างน้อย 2 ไฟล์" buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"
		return
	end if
	set fileArgs to ""
	repeat with theItem in theItems
		set fileArgs to fileArgs & " " & quoted form of (POSIX path of theItem)
	end repeat
	set parentDir to do shell script "dirname " & quoted form of (POSIX path of (item 1 of theItems))
	set outPath to parentDir & "/มัลติแคม.fcpxml"
	display notification "กำลังฟังเสียงทุกมุมกล้องเพื่อซิงก์ อาจใช้เวลาหลายนาที" with title "Ghostly790K"
	runGhostly(pkgDir, "sync" & fileArgs & " --out " & quoted form of outPath)
	set userChoice to button returned of (display dialog "ซิงก์มุมกล้องเสร็จแล้ว ✅" & return & outPath & return & return & ¬
		"นำเข้า FCP จะได้ multicam clip พร้อมตัดสลับมุม — เปิดเลยไหม" buttons {"ไว้ก่อน", "เปิดเลย"} default button "เปิดเลย" with title "Ghostly790K")
	if userChoice is "เปิดเลย" then do shell script "open " & quoted form of outPath
end doMulticam

-- SUBTITLE Cover: ไฮไลต์ป๊อบอัพ 2 บรรทัด (ขาว/ส้ม) จากซับเดิมในโปรเจกต์ FCP
on doCover(pkgDir)
	display dialog "SUBTITLE Cover" & return & return & ¬
		"1) ใน FCP: เลือกโปรเจกต์ → File → Export XML…" & return & ¬
		"2) เลือกไฟล์ที่ export มา (.fcpxmld / .fcpxml)" & return & ¬
		"3) โปรแกรมจะซ้อนไฮไลต์ป๊อบอัพ ขาว/ส้ม ตรงเวลาซับเดิมเป๊ะ — ซับเดิมไม่ถูกแตะ" ¬
		buttons {"ยกเลิก", "เลือกไฟล์"} default button "เลือกไฟล์" with title "Ghostly790K"
	set exported to choose file with prompt "เลือกไฟล์ Export XML จาก FCP (.fcpxmld / .fcpxml)"
	set exportedPath to POSIX path of exported
	display notification "กำลังสร้างไฮไลต์ป๊อบอัพ..." with title "Ghostly790K" subtitle "SUBTITLE Cover"
	set outputText to runGhostly(pkgDir, "cover " & quoted form of exportedPath)
	display dialog outputText & return & return & "นำเข้า FCP: File → Import → XML → เลือก Keep Both" ¬
		buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"
end doCover

-- ===== เครื่องมือกลาง =====

-- หาโฟลเดอร์แพ็กเกจแบบ AppleScript ล้วน (ไม่เรียกเชลล์ — เมนูต้องขึ้นทันที)
on packageDir()
	set appPath to POSIX path of (path to me)   -- ".../Ghostly790K-AI-Studio/Ghostly790K.app/"
	set AppleScript's text item delimiters to "/"
	set parts to text items of appPath
	if item -1 of parts is "" then set parts to items 1 thru -2 of parts
	set parts to items 1 thru -2 of parts       -- ตัดชื่อ .app ออก
	set pkgDir to parts as text
	set AppleScript's text item delimiters to ""
	return pkgDir
end packageDir

-- รัน ghostly: ปลดล็อก quarantine ครั้งแรก + กันเครื่องหลับ (caffeinate)
-- + เก็บ log + ไม่จำกัดเวลา (ไฟล์ใหญ่ได้) — งานเชลล์ทั้งหมดเกิดหลังผู้ใช้สั่งงานแล้ว
on runGhostly(pkgDir, argsText)
	set logPath to pkgDir & "/logs/ghostly.log"
	set shellCmd to "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; cd " & quoted form of pkgDir & " && mkdir -p logs; xattr -dr com.apple.quarantine . 2>/dev/null; chmod +x bin/ghostly 2>/dev/null; /usr/bin/caffeinate -im ./bin/ghostly " & argsText & " 2>>" & quoted form of logPath
	with timeout of 86400 seconds
		return do shell script shellCmd
	end timeout
end runGhostly

on tailLog(pkgDir)
	try
		return do shell script "tail -6 " & quoted form of (pkgDir & "/logs/ghostly.log")
	on error
		return ""
	end try
end tailLog

-- ติดตั้ง whisper + โมเดลถอดเสียงไทย จากในแอปโดยตรง (ปุ่ม "ติดตั้งซับให้เลย")
on installWhisper(pkgDir)
	display notification "กำลังติดตั้ง whisper + ดาวน์โหลดโมเดล (~550MB) มีแจ้งเตือนเมื่อเสร็จ" with title "Ghostly790K" subtitle "ติดตั้งซับไทยอัตโนมัติ"
	set logPath to pkgDir & "/logs/ghostly.log"
	set sh to "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; cd " & quoted form of pkgDir & ¬
		" && mkdir -p logs models; if ! command -v brew >/dev/null 2>&1; then exit 42; fi; " & ¬
		"command -v whisper-cli >/dev/null 2>&1 || brew install whisper-cpp; " & ¬
		"ls models/*.bin >/dev/null 2>&1 || ( /usr/bin/caffeinate -im curl -L --fail -o models/model.tmp " & ¬
		"'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin' " & ¬
		"&& mv models/model.tmp 'models/ggml-large-v3-turbo-q5_0.bin' ) || { rm -f models/model.tmp; exit 1; }"
	try
		with timeout of 86400 seconds
			do shell script sh & " 2>>" & quoted form of logPath
		end timeout
		display notification "ติดตั้งซับไทยเสร็จแล้ว ✅" with title "Ghostly790K"
	on error errorMessage number errorNumber
		if errorNumber is 42 then
			do shell script "open https://brew.sh"
			display dialog "ต้องติดตั้ง Homebrew ก่อนหนึ่งครั้ง (เปิดเว็บ brew.sh ให้แล้ว)" & return & ¬
				"ก็อปคำสั่งบรรทัดแรกในเว็บไปวางใน Terminal รอเสร็จ แล้วกลับมากด \"ติดตั้งซับให้เลย\" อีกครั้งครับ" ¬
				buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"
		else if errorNumber is not -128 then
			display dialog "ติดตั้งไม่สำเร็จ:" & return & errorMessage & return & return & tailLog(pkgDir) ¬
				buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"
		end if
	end try
end installWhisper

on whisperReady(pkgDir)
	try
		do shell script "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; command -v whisper-cli >/dev/null && ls " & quoted form of pkgDir & "/models/*.bin >/dev/null 2>&1"
		return true
	on error
		return false
	end try
end whisperReady

-- "…/คลิป.mp4" → "…/คลิป.fcpxml"
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
