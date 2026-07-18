-- Ghostly790K AI Final Cut Studio — แอปตัดต่ออัตโนมัติ (ภาษาไทย)
-- ลากไฟล์วิดีโอ (mov/mp4) มาวางบนไอคอนแอปนี้ หรือดับเบิลคลิกเพื่อเลือกไฟล์
-- แล้วพิมพ์คำสั่งภาษาไทย เช่น
--   "คัตเสียงคลิปนี้โดยเน้นประโยคสำคัญที่น่าสนใจ ความยาวเหลือไม่เกิน 3 นาที"
-- ได้ไฟล์ .fcpxml ที่เปิดใน Final Cut Pro ได้ทันที ฟุตเทจออนไลน์

property defaultCommand : "คัตเสียงคลิปนี้โดยเน้นประโยคสำคัญที่น่าสนใจ ความยาวเหลือไม่เกิน 3 นาที ใส่ซับไตเติ้ล"

on open theItems
	processFiles(theItems)
end open

on run
	set theFile to choose file with prompt "เลือกไฟล์วิดีโอที่จะตัดต่อ (mov / mp4)"
	processFiles({theFile})
end run

on processFiles(theItems)
	-- โฟลเดอร์แพ็กเกจ = โฟลเดอร์ที่มีทั้งแอปนี้และ bin/ghostly
	set appPath to POSIX path of (path to me)
	set pkgDir to do shell script "dirname " & quoted form of appPath

	-- ถามคำสั่งครั้งเดียว ใช้กับทุกไฟล์ที่ลากมา
	set dialogResult to display dialog "คำสั่งตัดต่อ (พิมพ์ภาษาไทยได้เลย)" default answer defaultCommand buttons {"ยกเลิก", "เริ่มตัดต่อ"} default button "เริ่มตัดต่อ" with title "Ghostly790K"
	if button returned of dialogResult is "ยกเลิก" then return
	set editCommand to text returned of dialogResult
	if editCommand is "" then set editCommand to defaultCommand

	repeat with theItem in theItems
		set videoPath to POSIX path of theItem
		try
			set outPath to my fcpxmlPath(videoPath)
			-- ปลดล็อก quarantine + ใช้โมเดล whisper ใน models/ อัตโนมัติ (ถ้ามี)
			set shellCmd to "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; cd " & quoted form of pkgDir & " && xattr -dr com.apple.quarantine . 2>/dev/null; chmod +x bin/ghostly 2>/dev/null; MODEL=$(ls models/*.bin 2>/dev/null | head -1); EXTRA=\"\"; if [ -n \"$MODEL\" ] && command -v whisper-cli >/dev/null 2>&1; then EXTRA=\"--model $MODEL\"; fi; ./bin/ghostly auto " & quoted form of videoPath & " --command " & quoted form of editCommand & " --remember --out " & quoted form of outPath & " $EXTRA"
			do shell script shellCmd
			set userChoice to button returned of (display dialog "เสร็จแล้ว ✅" & return & outPath & return & return & "เปิดใน Final Cut Pro เลยไหม" buttons {"ไว้ก่อน", "เปิดเลย"} default button "เปิดเลย" with title "Ghostly790K")
			if userChoice is "เปิดเลย" then
				do shell script "open " & quoted form of outPath
			end if
		on error errorMessage
			display dialog "มีข้อผิดพลาดกับไฟล์:" & return & videoPath & return & return & errorMessage buttons {"ตกลง"} default button "ตกลง" with title "Ghostly790K"
		end try
	end repeat
end processFiles

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
