// LaunchBar Action Script

const NO_MATCHES = {"title": "No matches"}

function getSnippetsFolder() {
    return Action.preferences.snippetsFolder;
}

function basename(fileName) {
    return fileName.slice(0, fileName.lastIndexOf("."))
}

function listFiles(folder) {
    return File.getDirectoryContents(folder)
        .sort()
        .map(basename)
        .map(name => ({
            title: name,
            action: "firstFile",
            actionArgument: name,
            actionReturnsItems: true
        }))
}

function run() {
    const snippetsFolder = getSnippetsFolder()
    const settingsItem = {
        'title' : 'Choose Snippets Folder',
        'action' : 'setFolder',
        'label' : 'Choose',
        'subtitle' : snippetsFolder ?? ""
    }

    if (snippetsFolder) {
        return listFiles(snippetsFolder).concat([settingsItem])
    } else {
        return [settingsItem]
    }
}

function invokeCLI(folder, string) {
    const result = LaunchBar.execute(
        '/usr/bin/env', 'ruby' , 'snibbets.rb',
        '-o', 'launchbar',
        '-s', encodeURI(folder),
        encodeURI(string)
    );
    return result ? JSON.parse(result) : NO_MATCHES
}

function firstFile(string) {
    const result = runWithString(string)
    return result !== NO_MATCHES ? result[0].children : result
}

function runWithString(string) {
    return invokeCLI(getSnippetsFolder(), string)
}

function hide() {
    LaunchBar.openCommandURL('hide'); // for some reason LaunchBar.hide() doesn't execute, but this does. Sometimes.
    LaunchBar.hide();
}

function copyIt(item) {
    LaunchBar.setClipboardString(item);
    hide()
}

function pasteIt(item) {
    LaunchBar.paste(item);
    hide()
}

function promptForFolder(defaultFolder) {
    const applescript = `\
set _default to POSIX file "${defaultFolder}" as alias
set _folder to choose folder with prompt "Select Snippets Folder" default location _default
return POSIX path of _folder`
    return LaunchBar.executeAppleScript(applescript)
}

function setFolder(item) {
    const defaultFolder = getSnippetsFolder() ?? LaunchBar.homeDirectory
    const selectedFolder = promptForFolder(defaultFolder)
    if (selectedFolder && selectedFolder.trim().length > 0) {
        Action.preferences.snippetsFolder = selectedFolder.trim();
    }
}
