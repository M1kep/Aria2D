//
//  DownloadsViewController.swift
//  Aria2D
//
//  Created by xjbeta on 16/2/19.
//  Copyright © 2016年 xjbeta. All rights reserved.
//

import Cocoa
import RealmSwift

class DownloadsViewController: NSViewController {
	@IBOutlet var downloadsTableView: DownloadsTableView!
	
	
	
	@IBAction func cellDoubleAction(_ sender: Any) {
		switch ViewControllersManager.shared.selectedRow {
		case .completed:
			ViewControllersManager.shared.openSelected()
		case .baidu:
            if downloadsTableView.selectedRowIndexes.count == 1 {
                let row = downloadsTableView.selectedRowIndexes.first!
                let data = DataManager.shared.data(PCSFile.self)[row]
				if data.isdir {
					Baidu.shared.selectedPath = data.path
                }
                if data.isBackButton {
					Baidu.shared.selectedPath = data.backParentDir
				}
			}
		default:
			break
		}
	}
	

	
	@IBOutlet var downloadsTableViewMenu: DownloadsMenu!
	@IBOutlet var baiduFileListMenu: BaiduFileListMenu!
	

	var dlinksProgress: BaiduDlinksProgress!
	
//    var previewViewController: PreviewViewController?
    
	
	override func viewDidLoad() {
		super.viewDidLoad()
        ViewControllersManager.shared.selectedRow = .downloading
		initNotification()
	}
	

    
        
    /*
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 &&
            downloadsTableView.selectedRowIndexes.count > 0 &&
            ViewControllersManager.shared.selectedRow != .baidu {
            performSegue(withIdentifier: showPreviewViewController, sender: self)
        } else {
            super.keyDown(with: event)
        }
    }
    */


	override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        
        
//        if segue.identifier == .showPreviewViewController {
//            if let vc = segue.destinationController as? PreviewViewController {
//                vc.dataSource = self
//                vc.delegate = self
//            }
//        } else
            
			
		if segue.identifier == .showBaiduDlinksProgress {
			if let vc = segue.destinationController as? BaiduDlinksProgress {
				vc.dataSource = self
			}
        } else if segue.identifier == .showOptionsWindow {
            if let wc = segue.destinationController as? NSWindowController,
                let vc = wc.contentViewController as? OptionsViewController,
                let gid = self.selectedObjects(Aria2Object.self).first?.gid {
                
                Aria2.shared.getOption(gid) {
                    vc.options = $0
                    vc.gid = gid
                }
            }
        } else if segue.identifier == .showStatusWindow {
            if let wc = segue.destinationController as? NSWindowController,
                let vc = wc.contentViewController as? StatusViewController,
                let gid = self.selectedObjects(Aria2Object.self).first?.gid {
                Aria2.shared.initData(gid) {
                    if let json = try? JSONSerialization.jsonObject(with: $0, options: .mutableContainers),
                        let dic = json as? [String: Any],
                        let result = dic["result"] as? [String: Any] {
                        vc.result = result
                    }
                }
			}
		}
	}
	

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
}



// MARK: - TableView
extension DownloadsViewController: NSTableViewDelegate, NSTableViewDataSource {
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		switch ViewControllersManager.shared.selectedRow {
		case .downloading, .completed, .removed:
			downloadsTableView.menu = downloadsTableViewMenu
			return DataManager.shared.data(Aria2Object.self).count
		case .baidu:
			downloadsTableView.menu = baiduFileListMenu
			return DataManager.shared.data(PCSFile.self).count
		default:
			return 0
		}
	}
	
	
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		
		switch ViewControllersManager.shared.selectedRow {
		case .downloading, .completed, .removed:
			if let cell = tableView.makeView(withIdentifier: .downloadsTableCell, owner: self) as? DownloadsTableCellView {
				if let data = DataManager.shared.data(Aria2Object.self)[safe: row] {
					cell.setData(data)
				}
				return cell
			}
		case .baidu:
			if let cell = tableView.makeView(withIdentifier: .baiduFileListCell, owner: self) as? BaiduFileListCellView {
				if let data = DataManager.shared.data(PCSFile.self)[safe: row] {
					cell.setData(data)
				}
				return cell
			}
		default:
			break
		}
		return nil
	}
	
	func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
		rowView.canDrawSubviewsIntoLayer = true
	}
	

	
	
	func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
		return downloadsTableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("DownloadsTableRowView"), owner: self) as? DownloadsTableRowView
		
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		downloadsTableView.setSelectedIndexs()
	}
	
}

// MARK: - MenuDelegate
extension DownloadsViewController: NSMenuDelegate {
	func menuWillOpen(_ menu: NSMenu) {
		downloadsTableView.setSelectedIndexs()
		if menu == baiduFileListMenu {
			baiduFileListMenu.initItemState()
		}
	}
}




extension DownloadsViewController {
	
	
	func initNotification() {
		downloadsTableView.initNotification()
		downloadsTableView.setRealmNotification()
		NotificationCenter.default.addObserver(self, selector: #selector(getDlinks), name: .getDlinks, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(deleteBaiduFile), name: .deleteFile, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showOptions), name: .showOptionsWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showStatus), name: .showStatusWindow, object: nil)
		
	}

	
	@objc func getDlinks() {
		let group = DispatchGroup()
		let data = selectedObjects(PCSFile.self).filter {
			!$0.isBackButton && !$0.isdir
		}
		
		switch data.count {
		case 0:
			return
		case 1...5:
			download(data: data, group: group)
		default:
			performSegue(withIdentifier: .showBaiduDlinksProgress, sender: self)
		}
		
	}
	
	func download(data: [PCSFile], group: DispatchGroup) {
		var dlinks = [[Any]](repeating: [], count: data.count)
		data.map {
			$0.path
			}.enumerated().forEach { (arg) in
				let (i, path) = arg
				group.enter()
				Baidu.shared.getDownloadUrls(FromPCS: path) {
					dlinks[i] = [$0, URL(fileURLWithPath: path).lastPathComponent]
					group.leave()
				}
		}
		group.notify(queue: .main) {
			dlinks.forEach {
				Aria2.shared.addUri(fromBaidu: $0[0] as! [String], name: $0[1] as! String)
			}
		}
	}
	
    @objc func showOptions(_ notification: Notification) {
        performSegue(withIdentifier: .showOptionsWindow, sender: self)
    }
    
    @objc func showStatus(_ notification: Notification) {
        performSegue(withIdentifier: .showStatusWindow, sender: self)
	}
	
	@objc func deleteBaiduFile() {
        Baidu.shared.delete(selectedObjects(PCSFile.self).filter({ !$0.isBackButton }).map({ $0.path }))
	}

	func selectedObjects<T: Object>(_ type: T.Type) -> [T] {
		return DataManager.shared.data(type).enumerated().filter {
			ViewControllersManager.shared.selectedIndexs.contains($0.offset)
			}.map {
				$0.element
		}
	}
	
	
}

extension DownloadsViewController: BaiduDlinksDataSource {
	func selectedObjects() -> [PCSFile] {
		return selectedObjects(PCSFile.self).filter {
			!$0.isBackButton && !$0.isdir
		}
	}
}
//extension DownloadsViewController: PreviewViewDataSource, PreviewViewDelegate {
//    func dataOfPreviewObjects() -> [TaskObject] {
//        return DataManager.shared.data(TaskObject.self).enumerated().filter {
//            downloadsTableView.selectedRowIndexes.contains($0.offset)
//            }.map {
//                $0.element
//        }
//    }
//    func selectedRowIndexes() -> IndexSet {
//        return downloadsTableView.selectedRowIndexes
//    }
//    
//    func preview(handel event: NSEvent) {
//        self.downloadsTableView.keyDown(with: event)
//    }
//}
