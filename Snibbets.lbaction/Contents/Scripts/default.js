// LaunchBar Action Script

const NO_MATCHES = {"title": "No matches"}

function getSnippetsFolder() {
    return Action.preferences.snippetsFolder;
}

function run() {
	settingsItem = {
		'title' : 'Choose Snippets Folder',
		'action' : 'setFolder',
		'label' : 'Choose',
		'subtitle' : getSnippetsFolder()
	}

    if (getSnippetsFolder()) {
        const files = File
            .getDirectoryContents(getSnippetsFolder())
            .sort()
            .map(fileName => {
                return {
                    title: fileName.slice(0, -3),
                    action: "firstFile",
                    actionArgument: fileName.slice(0, 3),
                    actionReturnsItems: true
                }
            })
        return files.concat([settingsItem])
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

function copyIt(item) {
	LaunchBar.setClipboardString(item);
	LaunchBar.openCommandURL('hide'); // for some reason LaunchBar.hide() doesn't execute, but this does. Sometimes.
	LaunchBar.hide();
}

function pasteIt(item) {
	LaunchBar.openCommandURL('hide');
	LaunchBar.paste(item);
	LaunchBar.hide();
}

function setFolder(item) {
  LaunchBar.displayInLargeType({
      title: 'Choosing folder'
  });
  var defaultFolder = LaunchBar.homeDirectory;
  if (Action.preferences.snippetsFolder) {
  	defaultFolder = Action.preferences.snippetsFolder;
  }
  var k = LaunchBar.executeAppleScript(
   'set _default to POSIX file "' + defaultFolder + '" as alias \n' +
   'set _folder to choose folder with prompt "Select Snippets Folder" default location _default \n' +
   ' return POSIX path of _folder');
  if (k && k.length > 0) {
    Action.preferences.snippetsFolder = k.trim();
  }
}
