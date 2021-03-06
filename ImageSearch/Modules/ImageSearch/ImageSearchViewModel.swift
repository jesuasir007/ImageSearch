//
//  ImageSearchViewModel.swift
//  ImageSearch
//
//  Created by Denis Simon on 02/19/2020.
//  Copyright © 2020 Denis Simon. All rights reserved.
//

import Foundation
import SwiftEvents

class ImageSearchViewModel {
    
    var apiService: APIService
    
    private(set) var data = [ImageSearchResults]() {
        didSet {
            updatesInData?()
        }
    }
    
    // Closure-based delegates
    var updatesInData: (() -> ())? = nil
    var resetSearchBar: (() -> ())? = nil
    
    // Observable properties
    let showActivityIndicator = Observable<Bool>(false)
    let showToast = Observable<String>("")
    let collectionViewTopConstraint = Observable<Float>(0)
    
    init(apiService: APIService) {
        self.apiService = apiService
        
        // Get some random images at the app's start
        DispatchQueue.main.async {
            self.searchFlickr(for: "Random")
        }
    }
    
    func searchFlickr(for searchString: String) {
        
        showActivityIndicator.value = true
        
        searchFlickr(for: searchString) { [weak self] result in
            guard let self = self else { return }
            
            self.showActivityIndicator.value = false
            
            switch result {
            case .error(let error) :
                if error != nil {
                    self.showToast.value = "Error searching: \(error.debugDescription)"
                } else {
                    self.showToast.value = "Error searching"
                }
            case .done(let results):
                let count = results.searchResults.count
                if count > 1 {
                    self.showToast.value = "Found \(results.searchResults.count) images"
                } else {
                    self.showToast.value = "Found 1 image"
                }
            }
        }
    }
    
    private func searchFlickr(for searchString: String, completion: @escaping (Result<ImageSearchResults>) -> ()) {
        
        var apiURL: URL!
        if let url = apiService.constructUrl(for: searchString) {
            apiURL = url
        } else {
            return
        }
        
        apiService.get(url: apiURL) { [weak self] (data, error) in
            guard let self = self else { return }
            
            guard error == nil && data != nil else {
                DispatchQueue.main.async {
                    completion(Result.error(error))
                }
                return
            }

            do {
                guard
                    let resultsDictionary = try JSONSerialization.jsonObject(with: data!) as? [String: AnyObject],
                    let stat = resultsDictionary["stat"] as? String
                    else {
                        DispatchQueue.main.async {
                            completion(Result.error(nil))
                        }
                        return
                }

                if stat != "ok" {
                    DispatchQueue.main.async {
                        completion(Result.error(nil))
                    }
                    return
                }

                guard
                    let container = resultsDictionary["photos"] as? [String: AnyObject],
                    let photos = container["photo"] as? [[String: AnyObject]]
                    else {
                        DispatchQueue.main.async {
                            completion(Result.error(nil))
                        }
                        return
                }

                let photosFound: [Image] = photos.compactMap { photoObject in
                    guard
                        let imageID = photoObject["id"] as? String,
                        let farm = photoObject["farm"] as? Int,
                        let server = photoObject["server"] as? String,
                        let secret = photoObject["secret"] as? String
                        else {
                            return nil
                    }

                    let image = Image(imageID: imageID, farm: farm, server: server, secret: secret)

                    guard
                        let url = image.getImageURL(),
                        let data = try? Data(contentsOf: url as URL)
                        else {
                            return nil
                    }

                    if let thumbnailImage = Helpers.getImage(data: data) {
                        image.thumbnail = thumbnailImage
                        return image
                    } else {
                        return nil
                    }
                }

                let searchResults = ImageSearchResults(searchString: searchString, searchResults: photosFound)
                DispatchQueue.main.async {
                    self.data.insert(searchResults, at: 0)
                    completion(Result.done(searchResults))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(Result.error(error))
                }
            }
        }
    }
    
    func searchBarSearchButtonClicked(with searchBarText: String?) {
        guard let searchBarText = searchBarText else { return }
        if !searchBarText.isEmpty {
            searchFlickr(for: searchBarText)
            resetSearchBar?()
        }
    }
    
    func scrollUp() {
        if collectionViewTopConstraint.value != 0 {
            collectionViewTopConstraint.value = 0
        }
    }
    
    func scrollDown(_ searchBarHeight: Float) {
        if collectionViewTopConstraint.value == 0 {
            collectionViewTopConstraint.value = searchBarHeight * -1
        }
    }
    
    func getDataSource() -> ImagesDataSource {
        return ImagesDataSource(with: data)
    }
    
    func getData() -> [ImageSearchResults] {
        return data
    }
    
    func getImage(for indexPath: (section: Int, row: Int)) -> Image {
        return data[indexPath.section].searchResults[indexPath.row]
    }
    
    func getSearchString(for section: Int) -> String {
        return data[section].searchString
    }
    
    func getHeightOfCell(width: Float) -> Float {
        let baseWidth = AppConstants.ImageCollection.baseImageWidth
        if width > baseWidth {
            return baseWidth
        } else {
            return width
        }
    }
}
