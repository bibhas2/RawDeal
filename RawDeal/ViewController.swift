//
//  ViewController.swift
//  RawDeal
//
//  Created by Bibhas Bhattacharya on 3/12/18.
//  Copyright © 2018 Bibhas Bhattacharya. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        self.present(CameraController(), animated: true)
    }


}

