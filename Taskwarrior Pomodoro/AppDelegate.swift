//
//  AppDelegate.swift
//  Taskwarrior Pomodoro
//
//  Created by Adam Coddington on 12/5/15.
//  MIT Licensed
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    @IBOutlet weak var window: NSWindow!
    
    //MARK: Attributes -
    let taskPath = "/usr/local/bin/task"
    let statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSSquareStatusItemLength)
    var activeTaskId: String? = nil
    var activeTimer: NSTimer? = nil
    var activeTimerEnds: NSDate? = nil
    var activeMenuItem: NSMenuItem? = nil
    var pomodoroDuration:Double = 60 * 25
    var configuration: [String: String]? = nil
    let menu = NSMenu();
    var activeCountdownTimer: NSTimer? = nil
    var pomodorosLogUUID: String?
    var currentPomodorosLogUUID: String?
    var pomsPerLongBreak: Int = 4
    var activeTaskPomodorosLogUUID: String?
    
    let kPomsLongBreakCharacter = "-"
    let kPomsPomDoneCharacter = "🍅"

    
    //MARK: Menu Items Tags -
    let kTimerItemTag = 1
    let kActiveTaskSeparator1ItemTag = 2
    let kActiveTaskMenuItemTag = 3
    let kStopTaskMenuItemTag = 4
    let kActiveTaskSeparator2ItemTag = 5
    let kPendingTaskMenuItemTag = 6;
    let kQuitSeparatorMenuItemTag = 7;
    let kQuitMenuItemTag = 8;
    let kSyncSeparatorMenuItemTag = 7;
    let kSyncMenuItemTag = 9;
    let kPomodorosCountMenuItemTag = 10
    
    //MARK: Menu Items Titles -
    let kStopTitleFormat = "Stop (%02u:%02u remaining)"
    let kActiveTitlePrefix = "Active: "

    //MARK: NSApplicationDelegate -
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
        configuration = getConfigurationSettings()
        
        if let button = statusItem.button {
            button.image = NSImage(named: "StatusBarButtonImage")
            button.action = Selector("printQuote:")
        }
        
        menu.delegate = self
        statusItem.menu = menu
    }
    
    //MARK: NSMenuDelegate -
    func menuWillOpen(menu: NSMenu) {
        updateMenuItems();
        startCountdownTimer()
    }
    
    func menuDidClose(menu: NSMenu) {
        stopCountdownTimer()
    }

    
    //MARK: API -
    func startCountdownTimer() {
        if activeTimerEnds != nil {
            activeCountdownTimer = NSTimer(
                timeInterval: 1.0,
                target: self,
                selector: "updateTaskTimer",
                userInfo: nil,
                repeats: true
            )
            NSRunLoop.currentRunLoop().addTimer(self.activeCountdownTimer!, forMode: NSEventTrackingRunLoopMode)
        }
    }
    
    func stopCountdownTimer() {
        activeCountdownTimer?.invalidate();
        activeCountdownTimer = nil
    }
    
    func updateMenuItems(aNotification: NSNotification){
        updateMenuItems()
    }
    
    func updateMenuItems() {
        setupStatsMenuItems()
        setupActiveTaskMenuItem()
        setupSyncMenuItem()
        setupQuitMenuItem()
        setupTaskListMenuItems()
    }
    
    func setupStatsMenuItems() {
        let pomodoros = getPomodorosCountMenuItem()
        
        if let title = getPomodorosCountTitle() {
            pomodoros.hidden = false
            pomodoros.title = title
        } else {
            pomodoros.hidden = true
        }
    }
    
    func setupActiveTaskMenuItem() {
        let activeSeparator1MenuItem = getActiveSeparatorMenuItem(1)
        let activeTaskMenuItem = getActiveTaskMenuItem()
        let stopTaskMenuItem = getStopTaskMenuItem()
        getActiveSeparatorMenuItem(2)
        
        
        if activeTaskId != nil {
            activeSeparator1MenuItem.hidden = false
            activeTaskMenuItem.hidden = false
            stopTaskMenuItem.hidden = false
            let taskDescription = getActiveTaskDescription()
            activeTaskMenuItem.title = "\(kActiveTitlePrefix) \(taskDescription)"
            updateTaskTimer()
        } else {
            activeSeparator1MenuItem.hidden = true
            activeTaskMenuItem.hidden = true
            stopTaskMenuItem.hidden = true
        }
    }
    
    func setupSyncMenuItem() {
        guard menu.itemWithTag(kSyncMenuItemTag) == nil else {
            return
        }
        
        var hidden = true;
        if configuration!["taskd.server"] != nil {
            hidden = false;
        }
        
        let syncSeparator = separatorWithTag(kSyncSeparatorMenuItemTag)
        syncSeparator.hidden = hidden;
        
        let syncMenuItem = NSMenuItem(title: "Synchronize", action: Selector("sync:"), keyEquivalent: "s")
        syncMenuItem.tag = kSyncMenuItemTag
        syncMenuItem.hidden = hidden;
        menu.addItem(syncMenuItem)
    }
    
    func setupQuitMenuItem() {
        guard menu.itemWithTag(kQuitMenuItemTag) == nil else {
            return
        }
        
        separatorWithTag(kQuitSeparatorMenuItemTag)
        
        let quitMenuItem = NSMenuItem(title: "Quit Taskwarrior Pomodoro", action: Selector("terminate:"), keyEquivalent: "q")
        quitMenuItem.tag = kQuitMenuItemTag
        menu.addItem(quitMenuItem)
    }
    
    func setupTaskListMenuItems() {
        clearOldTasks()
        
        let tasks = getPendingTasks();
        
        for task in tasks {
            if let description = task["description"].string {
                if let uuid = task["uuid"].string {
                    let menuItem = NSMenuItem(
                        title: description,
                        action: Selector("setActiveTask:"),
                        keyEquivalent: ""
                    )
                    menuItem.representedObject = uuid
                    menuItem.tag = kPendingTaskMenuItemTag
                    let index = menu.indexOfItemWithTag(kSyncSeparatorMenuItemTag)
                    menu.insertItem(menuItem, atIndex: index)
                }
            }
        }
    }
    
    func getConfigurationSettings(path: String = "~/.taskrc") -> [String: String] {
        var configurationSettings = [String: String]()
        
        let location = NSString(string: path).stringByExpandingTildeInPath
        let fileContent = try? NSString(contentsOfFile: location, encoding: NSUTF8StringEncoding) as String
        let fileContentLines = fileContent?.characters.split{$0 == "\n"}.map(String.init)
        
        for line in fileContentLines! {
            var equalIndex: String.CharacterView.Index? = nil;

            if let idx = line.characters.indexOf("=" as Character) {
                equalIndex = idx
            }
            
            if line.hasPrefix("include ") {
                var pathLine = line;
                let prefixRange = line.startIndex..<line.startIndex.advancedBy(8)
                pathLine.removeRange(prefixRange)
                for (k, v) in getConfigurationSettings(pathLine) {
                    configurationSettings[k] = v
                }
            } else if equalIndex != nil {
                let configurationKey = line.substringWithRange(
                    Range(start: line.startIndex, end: equalIndex!)
                    ).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
                let configurationValue = line.substringFromIndex(
                    equalIndex!.successor()
                    ).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
                configurationSettings[configurationKey] = configurationValue
            }
        }
        
        return configurationSettings
    }
    
    func getPendingTasks() -> [JSON] {
        var pendingArguments = ["status:Pending"]
        
        if let definedDefaultFilter = configuration!["pomodoro.defaultFilter"] {
            pendingArguments = [definedDefaultFilter] + pendingArguments
        }
        
        return getTasksUsingFilter(pendingArguments)
    }
    
    func getTodaysPomodorosLog() -> JSON? {
        let logFilter = ["status:Completed", "Pomodoro", "entry:today", "limit:1"]
        let tasks = getTasksUsingFilter(logFilter)
        
        guard !tasks.isEmpty else {
            return nil
        }
        
        currentPomodorosLogUUID = tasks[0]["uuid"].string
        
        return tasks[0]
    }
    
    func getTasksUsingFilter(filter: [String]) -> [JSON] {
        let task = NSTask()
        task.launchPath = taskPath
        task.arguments = ["rc.json.array=off"] + filter + ["export"]
        
        let pipe = NSPipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = NSString(data: data, encoding: NSUTF8StringEncoding) as! String
        
        let taskListStrings = output.characters.split{$0 == "\n"}.map(String.init)
        
        var taskList = [JSON]()
        for taskListString in taskListStrings {
            if let dataFromString = taskListString.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true) {
                let taskData = JSON(data: dataFromString)
                taskList.append(taskData)
            }
        }
        
        return taskList;
    }
    
    func getPomodorosCountTitle() -> String? {
        guard let log = getTodaysPomodorosLog() else {
            return nil
        }
        
        let count = log["annotations"].count
        var title = ""
        
        for i in 0..<count {
            if (i + 1) % pomsPerLongBreak == 1 && i != 0 {
                title += kPomsLongBreakCharacter
            }
            
            title += kPomsPomDoneCharacter
        }
        
        return title
    }
    
    
    func clearOldTasks() {
        while let item = menu.itemWithTag(kPendingTaskMenuItemTag) {
            menu.removeItem(item)
        }
    }
    
    func getStopTaskMenuItem() -> NSMenuItem {
        if let item = menu.itemWithTag(kStopTaskMenuItemTag) {
            return item;
        }
        
        let stopItem = NSMenuItem(
            title: "Stop",
            action: Selector("stopActiveTask:"),
            keyEquivalent: "s"
        )
        stopItem.tag = kStopTaskMenuItemTag
        menu.addItem(stopItem)
        
        return stopItem;
    }
    
    func getActiveSeparatorMenuItem(index: Int) -> NSMenuItem {
        var tag: Int = 1
        
        switch (index) {
        case 1:
            tag = kActiveTaskSeparator1ItemTag
        case 2:
            tag = kActiveTaskSeparator2ItemTag
        default:
            tag = kActiveTaskSeparator1ItemTag;
        }
        
        let separator = menu.itemWithTag(tag) ?? separatorWithTag(tag);
        
        return separator
    }
    
    func getActiveTaskMenuItem() -> NSMenuItem {
        if let item = menu.itemWithTag(kActiveTaskMenuItemTag) {
            return item
        }
        
        let taskDescription = getActiveTaskDescription()
        let activeItem = NSMenuItem(
            title: "\(kActiveTitlePrefix) \(taskDescription)",
            action: "",
            keyEquivalent: ""
        )
        activeItem.enabled = false
        activeItem.tag = kActiveTaskMenuItemTag
        menu.addItem(activeItem)
        
        return activeItem
    }
    
    func getPomodorosCountMenuItem() -> NSMenuItem {
        if let item = menu.itemWithTag(kPomodorosCountMenuItemTag) {
            return item
        }
        
        let pomsItem = NSMenuItem(
            title: "",
            enabled: false,
            tag: kPomodorosCountMenuItemTag
        )
        
        menu.addItem(pomsItem)
        return pomsItem
    }
    
    func separatorWithTag(tag: Int) -> NSMenuItem {
        let separator = NSMenuItem.separatorItem()
        separator.tag = tag
        menu.addItem(separator);
        return separator
    }
    
    func getActiveTaskDescription() -> String {
        if activeTaskId == nil {
            return "N/A"
        }
        
        var description: String = ""
        
        let task = NSTask()
        task.launchPath = taskPath
        task.arguments = ["rc.json.array=off", activeTaskId!, "export"]
        
        let pipe = NSPipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = NSString(data: data, encoding: NSUTF8StringEncoding) as! String
        if let dataFromString = output.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true) {
            let taskData = JSON(data: dataFromString)
            if let thisDescription = taskData["description"].string {
                description = thisDescription
            }
        }
        
        return description
    }
    
    func sync(aNotification: NSNotification) {
        sync()
    }
    
    func sync() {
        let task = NSTask()
        task.launchPath = taskPath
        task.arguments = ["sync"]
        task.launch()
        task.waitUntilExit()
    }
    
    func stopActiveTask(aNotification: NSNotification) {
        stopActiveTask()
    }
    
    func stopActiveTask() {
        if activeTimer != nil {
            activeTimer!.invalidate()
            activeTimer = nil
        }
        
        activeTimerEnds = nil;
        updateTaskTimer()

        let task = NSTask()
        task.launchPath = taskPath
        task.arguments = [activeTaskId!, "stop"]
        task.launch()
        task.waitUntilExit()
        
        activeTaskId = nil
        updateMenuItems()
    }
    
    func startTaskById(taskId: String) {
        activeTaskId = taskId
        
        let task = NSTask()
        task.launchPath = taskPath
        task.arguments = [taskId, "start"]
        task.launch()
        task.waitUntilExit()
        activeTaskPomodorosLogUUID = currentPomodorosLogUUID
        
        updateMenuItems()
    }
    
    func runPostCompletionHooks(taskId: String) {
        if let postCompletionCommand = configuration!["pomodoro.postCompletionCommand"] {
            let errorPipe = NSPipe()
            let errorFile = errorPipe.fileHandleForReading
            
            let task = NSTask()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", "\(postCompletionCommand) \(taskId)"]
            task.standardError = errorPipe
            task.launch()
            task.waitUntilExit()
            
            let stderr = stringFromFileAndClose(errorFile)
            
            if task.terminationStatus != 0 {
                let alert:NSAlert = NSAlert();
                alert.messageText = "Post-Hook Error";
                alert.informativeText = "An error was encountered when running your post-hook command: `\(stderr)`.";
                alert.runModal();
            }
        }
    }
    
    private func stringFromFileAndClose(file: NSFileHandle) -> String {
        let data = file.readDataToEndOfFile()
        file.closeFile()
        let output = NSString(data: data, encoding: NSUTF8StringEncoding) as String?
        return output ?? ""
    }
    
    func timerExpired() {
        if activeTimer != nil {
            activeTimer!.invalidate()
            activeTimer = nil
        }

        let taskId = activeTaskId;

        stopActiveTask()
        logPomodoroForTaskDone(taskId)

        let alert:NSAlert = NSAlert();
        alert.messageText = "Break time!";
        alert.informativeText = "Taskwarrior Pomodoro";
        alert.runModal();

        runPostCompletionHooks(taskId!)
    }
    
    func logPomodoroForTaskDone(taskId: String?) {
        let uuid = taskId ?? ""
        
        if let logId = activeTaskPomodorosLogUUID {
            let task = NSTask()
            task.launchPath = taskPath
            task.arguments = [logId, "annotate", "\"Pomodoro uuid:\(uuid)\""]
            task.launch()
            task.waitUntilExit()
        }
    }
    
    func setActiveTask(sender: AnyObject) {
        if activeTaskId != nil{
            stopActiveTask()
        }
        startTaskById(sender.representedObject as! String)
        
        activeTimer = NSTimer.scheduledTimerWithTimeInterval(
            pomodoroDuration,
            target: self,
            selector: "timerExpired",
            userInfo: nil,
            repeats: false
        )
        
        let now = NSDate()
        activeTimerEnds = now.dateByAddingTimeInterval(pomodoroDuration);
    }
    
    func updateTaskTimer() {
        let date = NSDate()
        
        let minutesFrom = activeTimerEnds?.minutesFrom(date) ?? 25
        let secondsFrom = (activeTimerEnds?.secondsFrom(date) ?? 1500) - minutesFrom * 60
        
        getStopTaskMenuItem().title = String(format: kStopTitleFormat, minutesFrom, secondsFrom)
    }
}

extension NSDate {
    func yearsFrom(date:NSDate) -> Int{
        return NSCalendar.currentCalendar().components(.Year, fromDate: date, toDate: self, options: []).year
    }
    func monthsFrom(date:NSDate) -> Int{
        return NSCalendar.currentCalendar().components(.Month, fromDate: date, toDate: self, options: []).month
    }
    func weeksFrom(date:NSDate) -> Int{
        return NSCalendar.currentCalendar().components(.WeekOfYear, fromDate: date, toDate: self, options: []).weekOfYear
    }
    func daysFrom(date:NSDate) -> Int{
        return NSCalendar.currentCalendar().components(.Day, fromDate: date, toDate: self, options: []).day
    }
    func hoursFrom(date:NSDate) -> Int{
        return NSCalendar.currentCalendar().components(.Hour, fromDate: date, toDate: self, options: []).hour
    }
    func minutesFrom(date:NSDate) -> Int{
        return NSCalendar.currentCalendar().components(.Minute, fromDate: date, toDate: self, options: []).minute
    }
    func secondsFrom(date:NSDate) -> Int{
        return NSCalendar.currentCalendar().components(.Second, fromDate: date, toDate: self, options: []).second
    }
    func offsetFrom(date:NSDate) -> String {
        if yearsFrom(date)   > 0 { return "\(yearsFrom(date))y"   }
        if monthsFrom(date)  > 0 { return "\(monthsFrom(date))M"  }
        if weeksFrom(date)   > 0 { return "\(weeksFrom(date))w"   }
        if daysFrom(date)    > 0 { return "\(daysFrom(date))d"    }
        if hoursFrom(date)   > 0 { return "\(hoursFrom(date))h"   }
        if minutesFrom(date) > 0 { return "\(minutesFrom(date))m" }
        if secondsFrom(date) > 0 { return "\(secondsFrom(date))s" }
        return ""
    }
}

extension NSMenuItem {
    convenience init(title: String, enabled: Bool, tag: NSInteger) {
        self.init(
            title: title,
            action: "",
            keyEquivalent: ""
        )
        
        self.enabled = enabled
        self.tag = tag
    }
}

