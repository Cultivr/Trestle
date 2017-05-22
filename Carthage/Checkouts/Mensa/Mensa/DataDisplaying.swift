//
//  DataDisplaying.swift
//  Mensa
//
//  Created by Jordan Kay on 6/21/16.
//  Copyright © 2016 Jordan Kay. All rights reserved.
//

/// Protocol for view controllers to adopt in order to display data (sections of items) in a table or collection view.
public protocol DataDisplaying: Displaying {
    associatedtype DataSourceType: DataSource
    associatedtype TableViewType: UITableView = UITableView
    associatedtype CollectionViewType: UICollectionView = UICollectionView
    
    // The source of the data to display.
    var dataSource: DataSourceType { get }
    
    // The context (table or collection view and its properties) for displaying the data.
    var displayContext: DataDisplayContext { get }

    // Implementors should call `register` for each view controller type that they want to represent each item type displayed.
    func registerItemTypeViewControllerTypePairs()
    
    // Optionally specify data view properties.
    func setupDataView()
    
    // Optional functionality implementors can specify to modify a view that will be used to display a given item.
    func use(_ view: View, with item: Item, variant: DisplayVariant, displayed: Bool)
    
    // Handle scroll events.
    func handle(_ scrollEvent: ScrollEvent)
    
    // Specify which display variant should be used for the given item, other than the default.
    func variant(for item: Item, viewType: View.Type) -> DisplayVariant
    
    // How the given section is inset, if at all.
    func sectionInsets(for section: Int) -> UIEdgeInsets?
    
    // How the size of the item at the given index path is inset.
    func sizeInsets(for indexPath: IndexPath) -> UIEdgeInsets
    
    // Specify additional behavior to be executed when the data is reset.
    func reset()
}

public extension DataDisplaying {
    func registerItemTypeViewControllerTypePairs() {}
    func setupDataView() {}
    func use(_ view: View, with item: Item, variant: DisplayVariant, displayed: Bool) {}
    func handle(_ scrollEvent: ScrollEvent) {}
    func variant(for item: Item, viewType: View.Type) -> DisplayVariant { return DefaultDisplayVariant() }
    func sectionInsets(for section: Int) -> UIEdgeInsets? { return nil }
    func sizeInsets(for indexPath: IndexPath) -> UIEdgeInsets { return .zero }
    func reset() {}
}

public extension DataDisplaying where Self: UIViewController {
    var tableView: TableViewType? {
        return dataView as? TableViewType
    }
    
    var collectionView: CollectionViewType? {
        return dataView as? CollectionViewType
    }
    
    fileprivate(set) var dataView: DataView {
        get {
            return associatedObject(for: &dataViewKey) as! DataView
        }
        set {
            setAssociatedObject(newValue, for: &dataViewKey)
        }
    }
}

public extension DataDisplaying where Self: UIViewController, DataSourceType.Item == Item {
    // Reference the current number of sections of data.
    var sectionCount: Int {
        return dataMediator?.sectionCount ?? 0
    }
    
    // Call this method to set up a display context in a view controller by adding an appropriate data view as a subview.
    func setDisplayContext() {
        let dataView: UIView
        var tableViewCellSeparatorInset: CGFloat? = nil
        var hidesLastTableViewCellSeparator = false
        
        switch displayContext {
        case let .tableView(separatorInset, separatorPlacement):
            let tableView = TableViewType.init()
            tableViewCellSeparatorInset = separatorInset
            hidesLastTableViewCellSeparator = (separatorPlacement == .allCellsButLast)
            if separatorPlacement == nil {
                tableView.separatorStyle = .none
            } else if separatorPlacement != .default {
                tableView.tableFooterView = UIView()
                if separatorPlacement == .allCellsAndTop {
                    let frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 1 / UIScreen.main.scale)
                    tableView.tableHeaderView = UIView(frame: frame)
                    tableView.tableHeaderView?.backgroundColor = tableView.separatorColor
                }
            }
            dataView = tableView
            self.dataView = tableView
        case let .collectionView(layout):
            let collectionView = CollectionViewType.init(frame: .zero, collectionViewLayout: layout)
            collectionView.backgroundColor = .clear
            if #available (iOS 10, *) {
                collectionView.isPrefetchingEnabled = false
            }
            dataView = collectionView
            self.dataView = collectionView
        }
        
        view.addSubview(dataView)
        dataView.frame = view.bounds
        dataView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupDataView()
        
        let dataMediator = DataMediator(
            parentViewController: self,
            sections: { [unowned self] in self.dataSource.sections },
            variant: { [unowned self] in self.variant(for: $0, viewType: $1) },
            useViewWithItem: { [unowned self] in self.use($0, with: $1, variant: $2, displayed: $3) },
            handleScrollEvent: { [weak self] in self?.handle($0) },
            tableViewCellSeparatorInset: tableViewCellSeparatorInset,
            hidesLastTableViewCellSeparator: hidesLastTableViewCellSeparator,
            sectionInsets: { [unowned self] in self.sectionInsets(for: $0) },
            collectionViewSizeInsets: { [unowned self] in self.sizeInsets(for: $0) }
        )
        setAssociatedObject(dataMediator, for: &dataMediatorKey)
        
        if let tableView = dataView as? UITableView {
            tableView.delegate = dataMediator
            tableView.dataSource = dataMediator
            tableView.estimatedRowHeight = .defaultRowHeight
            tableView.rowHeight = UITableViewAutomaticDimension
        } else if let collectionView = dataView as? UICollectionView {
            collectionView.delegate = dataMediator
            collectionView.dataSource = dataMediator
        }
        
        registerItemTypeViewControllerTypePairs()
    }
    
    // Register a view controller type to use to display an item type.
    func register<Item, ViewController: UIViewController>(itemType: Item.Type, conformingTypes: [Any.Type] = [], viewType: View.Type, controllerType: ViewController.Type) where Item == ViewController.Item, ViewController: ItemDisplaying {
        dataMediator?.register(itemType: itemType, conformingTypes: conformingTypes, viewType: viewType, controllerType: controllerType)
    }
    
    //
    func prefetchContent(at indexPaths: [IndexPath], inScrollView scrollView: UIScrollView) {
        DispatchQueue.main.async {
            self.dataMediator?.prefetchContent(at: indexPaths, in: scrollView)
        }
    }
    
    // Call this method from the view controller to reload the data view.
    func reloadData() {
        resetData()
        DispatchQueue.main.async {
            self.dataView.reloadData()
        }
    }
    
    // Call this method from the view controller to reload the data at specific index paths in the data view.
    func reloadItems(at indexPaths: [IndexPath], animated: Bool = false) {
        resetData()
        var reload = {}
        if let tableView = dataView as? UITableView {
            reload = { tableView.reloadRows(at: indexPaths, with: .fade) }
        } else if let collectionView = dataView as? UICollectionView {
            reload = { collectionView.reloadItems(at: indexPaths) }
        }
        if animated {
            reload()
        } else {
            UIView.performWithoutAnimation(reload)
        }
    }
    
    // Call this method from the view controller to insert items into the data view.
    func insertItems(at indexPaths: [IndexPath], animated: Bool = false) {
        resetData()
        var insert = {}
        if let tableView = dataView as? UITableView {
            insert = { tableView.insertRows(at: indexPaths, with: .fade) }
        } else if let collectionView = dataView as? UICollectionView {
            insert = { collectionView.insertItems(at: indexPaths) }
        }
        if animated {
            insert()
        } else {
            UIView.performWithoutAnimation(insert)
        }
    }
    
    // Call this method to
    func insertSections(_ sections: IndexSet, animated: Bool = false) {
        resetData()
        var insert = {}
        if let tableView = dataView as? UITableView {
            insert = { tableView.insertSections(sections, with: .fade) }
        } else if let collectionView = dataView as? UICollectionView {
            insert = { collectionView.insertSections(sections) }
        }
        if animated {
            insert()
        } else {
            UIView.performWithoutAnimation(insert)
        }
    }
    
    // Call this method from the view controller to remove items from the data view.
    func removeItems(at indexPaths: [IndexPath], animated: Bool = false) {
        resetData()
        var remove = {}
        if let tableView = dataView as? UITableView {
            remove = { tableView.deleteRows(at: indexPaths, with: .fade) }
        } else if let collectionView = dataView as? UICollectionView {
            remove = { collectionView.deleteItems(at: indexPaths) }
        }
        if animated {
            remove()
        } else {
            UIView.performWithoutAnimation(remove)
        }
    }
}

private var dataViewKey = "displayViewKey"
private var dataMediatorKey = "dataMediatorKey"

private extension DataDisplaying where Self: UIViewController {
    var dataMediator: DataMediator<Item, View>? {
        return (dataView as? UITableView)?.dataSource as? DataMediator<Item, View> ?? (dataView as? UICollectionView)?.dataSource as? DataMediator<Item, View>
    }
    
    func resetData() {
        reset()
        dataMediator?.reset()
    }
}

private extension CGFloat {
    static let defaultRowHeight: CGFloat = 44
}