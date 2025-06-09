--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.
]] local config = {
    enabled = true,
    pluginName = "aicrimereport", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    configVersion = "1.0",
    callCoolDown = 60, -- Time in between calls in seconds
    clothingConfig = {
        -- Array of clothing items that will be whitelisted from triggering 911 calls
        whiteList = {
            {
                component = 8, -- Component ID for tops
                drawable = 0, -- Drawable ID for the item
                textures = {0} -- Texture ID for the item
            },
            {
                component = 3, -- Component ID for torsos
                drawable = 0, -- Drawable ID for the item
                textures = {0} -- Texture ID for the item
            },
            {
                component = 4, -- Component ID for pants
                drawable = 0, -- Drawable ID for the item
                textures = {0} -- Texture ID for the item
            }
        },
        -- ======================
        -- TOPS (component 8)
        -- ======================
        -- mp_m_freemode_01 (male)
        top = {
            [0] = {
                name = "T-Shirt",
                colors = {
                    [0] = "White",
                    [1] = "Red",
                    [2] = "Blue",
                    [3] = "Yellow",
                    [4] = "Pink",
                    [5] = "Green",
                    [6] = "Purple"
                }
            },
            [1] = {
                name = "Vest Top",
                colors = {
                    [0] = "Black",
                    [1] = "Grey",
                    [2] = "Navy",
                    [3] = "Red",
                    [4] = "Brown",
                    [5] = "Green"
                }
            },
            [2] = {
                name = "Tank Top",
                colors = {
                    [0] = "Black",
                    [1] = "White",
                    [2] = "Blue",
                    [3] = "Orange",
                    [4] = "Green",
                    [5] = "Yellow"
                }
            },
            [3] = {
                name = "Shirt",
                colors = {
                    [0] = "White",
                    [1] = "Black",
                    [2] = "Grey",
                    [3] = "Blue",
                    [4] = "Red",
                    [5] = "Orange"
                }
            },
            [4] = {
                name = "Flannel Shirt",
                colors = {
                    [0] = "Red",
                    [1] = "Blue",
                    [2] = "Green",
                    [3] = "Grey",
                    [4] = "Brown"
                }
            },
            [5] = {
                name = "Dress Shirt",
                colors = {
                    [0] = "White",
                    [1] = "Pink",
                    [2] = "Blue",
                    [3] = "Light Blue",
                    [4] = "Black"
                }
            },
            [6] = {
                name = "Polo Shirt",
                colors = {
                    [0] = "White",
                    [1] = "Red",
                    [2] = "Blue",
                    [3] = "Black",
                    [4] = "Green"
                }
            },
            [7] = {
                name = "Hoodie",
                colors = {
                    [0] = "Grey",
                    [1] = "Navy",
                    [2] = "Maroon",
                    [3] = "Black",
                    [4] = "Olive"
                }
            },
            [8] = {
                name = "Jersey",
                colors = {
                    [0] = "White/Red",
                    [1] = "Blue/White",
                    [2] = "Black/Gold",
                    [3] = "Green/White"
                }
            },
            [9] = {
                name = "Hawaiian Shirt",
                colors = {
                    [0] = "Red/White",
                    [1] = "Blue/White",
                    [2] = "Yellow/Green"
                }
            },
            [10] = {
                name = "Henley Shirt",
                colors = {
                    [0] = "White",
                    [1] = "Grey",
                    [2] = "Green",
                    [3] = "Navy"
                }
            },
            [11] = {
                name = "Short Sleeve",
                colors = {
                    [0] = "White",
                    [1] = "Black",
                    [2] = "Red",
                    [3] = "Blue"
                }
            },
            [12] = {
                name = "Long Sleeve Tee",
                colors = {[0] = "White", [1] = "Black", [2] = "Grey"}
            },
            [13] = {
                name = "Flannel Vest",
                colors = {[0] = "Red", [1] = "Green", [2] = "Blue"}
            },
            [14] = {
                name = "Thermal Shirt",
                colors = {[0] = "Black", [1] = "Grey", [2] = "Tan"}
            },
            [15] = {
                name = "Graphic Tee",
                colors = {
                    [0] = "White/Black",
                    [1] = "Grey/Red",
                    [2] = "Blue/Yellow"
                }
            },
            [16] = {
                name = "Dressy Shirt",
                colors = {
                    [0] = "White",
                    [1] = "Black",
                    [2] = "Navy",
                    [3] = "Maroon"
                }
            },
            [17] = {
                name = "Denim Shirt",
                colors = {[0] = "Blue", [1] = "Light Blue"}
            },
            [18] = {
                name = "Zip-Up Hoodie",
                colors = {
                    [0] = "Black",
                    [1] = "Grey",
                    [2] = "Red",
                    [3] = "Navy"
                }
            },
            [19] = {
                name = "Chambray Shirt",
                colors = {[0] = "Blue", [1] = "Grey"}
            },
            [20] = {
                name = "Work Shirt",
                colors = {[0] = "Yellow", [1] = "Blue", [2] = "Green"}
            },
            [21] = {name = "Open Top", colors = {[0] = "Black", [1] = "White"}},
            [22] = {name = "Peacoat", colors = {[0] = "Black", [1] = "Navy"}},
            [23] = {
                name = "Bomber Jacket",
                colors = {[0] = "Black", [1] = "Khaki", [2] = "Green"}
            },
            [24] = {
                name = "Leather Jacket",
                colors = {[0] = "Black", [1] = "Brown"}
            },
            [25] = {
                name = "Basketball Jersey",
                colors = {[0] = "Red", [1] = "Blue", [2] = "Green"}
            },
            [26] = {
                name = "Muscle Shirt",
                colors = {[0] = "Black", [1] = "White", [2] = "Red"}
            },
            [27] = {
                name = "City Polo",
                colors = {[0] = "White", [1] = "Black", [2] = "Blue"}
            },
            [28] = {
                name = "Sweatshirt",
                colors = {[0] = "Grey", [1] = "Navy", [2] = "Maroon"}
            },
            [29] = {
                name = "Camouflage Shirt",
                colors = {[0] = "Forest", [1] = "Desert", [2] = "Urban"}
            },
            [30] = {
                name = "Track Jacket",
                colors = {
                    [0] = "Black/White",
                    [1] = "Red/Black",
                    [2] = "Blue/White"
                }
            },
            [31] = {
                name = "Varsity Jacket",
                colors = {[0] = "Black/White", [1] = "Blue/White"}
            },
            [32] = {
                name = "Rain Jacket",
                colors = {[0] = "Yellow", [1] = "Orange"}
            },
            [33] = {
                name = "Puffer Jacket",
                colors = {[0] = "Black", [1] = "Navy"}
            },
            [34] = {
                name = "Jean Jacket",
                colors = {[0] = "Blue", [1] = "Black"}
            },
            [35] = {
                name = "Windbreaker",
                colors = {[0] = "Green", [1] = "Blue"}
            },
            [36] = {
                name = "Tank Top w/ Pattern",
                colors = {[0] = "Camo", [1] = "Floral"}
            },
            [37] = {
                name = "Sleeveless Hoodie",
                colors = {[0] = "Grey", [1] = "Black"}
            },
            [38] = {
                name = "Muscle Tee",
                colors = {[0] = "White", [1] = "Black"}
            },
            [39] = {
                name = "V-Neck Tee",
                colors = {[0] = "White", [1] = "Black"}
            },
            [40] = {
                name = "V-Neck Sweater",
                colors = {[0] = "Grey", [1] = "Navy"}
            },
            [41] = {
                name = "Dressy Top",
                colors = {[0] = "White", [1] = "Black"}
            },
            [42] = {
                name = "Floral Shirt",
                colors = {[0] = "Green/Red", [1] = "Blue/Yellow"}
            },
            [43] = {
                name = "Polo w/ Stripes",
                colors = {[0] = "Red/White", [1] = "Blue/White"}
            },
            [44] = {
                name = "Graphic Hoodie",
                colors = {[0] = "Black/White", [1] = "Grey/Red"}
            },
            [45] = {
                name = "Wind Jacket",
                colors = {[0] = "Yellow", [1] = "Black"}
            },
            [46] = {name = "Turtleneck", colors = {[0] = "Black", [1] = "Grey"}},
            [47] = {name = "Leather Vest", colors = {[0] = "Black"}},
            [48] = {name = "Denim Vest", colors = {[0] = "Blue"}},
            [49] = {
                name = "Vest w/ Hood",
                colors = {[0] = "Grey", [1] = "Navy"}
            },
            [50] = {
                name = "Form-fitting Tee",
                colors = {[0] = "White", [1] = "Black"}
            },
            [51] = {name = "Cardigan", colors = {[0] = "Brown", [1] = "Grey"}},
            [52] = {name = "Blazer", colors = {[0] = "Black", [1] = "Navy"}},
            [53] = {
                name = "Puffer Vest",
                colors = {[0] = "Black", [1] = "Olive"}
            },
            [54] = {
                name = "Track Top",
                colors = {[0] = "Red/White", [1] = "Blue/White"}
            },
            [55] = {
                name = "Crewneck Sweater",
                colors = {[0] = "Grey", [1] = "Navy"}
            },
            [56] = {name = "Gilet", colors = {[0] = "Black"}},
            [57] = {name = "Denim Overalls", colors = {[0] = "Blue"}},
            [58] = {name = "Leather Overalls", colors = {[0] = "Black"}},
            [59] = {
                name = "Tank Top w/ Graphic",
                colors = {[0] = "White/Red", [1] = "Black/Green"}
            },
            [60] = {
                name = "Rugby Shirt",
                colors = {[0] = "Black/White", [1] = "Blue/White"}
            },
            [61] = {
                name = "Sport Hoodie",
                colors = {[0] = "Red/Black", [1] = "Blue/White"}
            },
            [62] = {
                name = "Color-block Tee",
                colors = {[0] = "Black/White", [1] = "Grey/Red"}
            },
            [63] = {name = "Workman Shirt", colors = {[0] = "Yellow/Blue"}},
            [64] = {
                name = "Visored Tee",
                colors = {[0] = "White/Black", [1] = "Red/White"}
            },
            [65] = {name = "Festival Top", colors = {[0] = "Tie-Dye"}},
            [66] = {
                name = "Tech Jacket",
                colors = {[0] = "Black", [1] = "Grey"}
            },
            [67] = {
                name = "Padded Hoodie",
                colors = {[0] = "Grey", [1] = "Navy"}
            },
            [68] = {name = "Mesh Tank", colors = {[0] = "Black"}},
            [69] = {
                name = "Longline Tee",
                colors = {[0] = "White", [1] = "Black"}
            },
            [70] = {
                name = "Athletic Tee",
                colors = {[0] = "Grey", [1] = "Navy"}
            },
            [71] = {name = "Denim Shirt Vest", colors = {[0] = "Blue"}},
            [72] = {name = "Printed Shirt", colors = {[0] = "Floral"}},
            [73] = {
                name = "Canvas Jacket",
                colors = {[0] = "Khaki", [1] = "Olive"}
            },
            [74] = {
                name = "Motorcycle Leather Jacket",
                colors = {[0] = "Black"}
            },
            [75] = {name = "Varsity Hoodie", colors = {[0] = "Black/White"}},
            [76] = {name = "Festival Tank", colors = {[0] = "Tie-Dye"}},
            [77] = {name = "Flannel Shirt Vest", colors = {[0] = "Red/Black"}},
            [78] = {name = "Camo Shirt", colors = {[0] = "Forest Camo"}},
            [79] = {name = "High-Vis Shirt", colors = {[0] = "Yellow/Orange"}},
            [80] = {name = "Slim Tee", colors = {[0] = "Black"}},
            [81] = {name = "Muscle Tank", colors = {[0] = "White"}},
            [82] = {name = "Oversized Tee", colors = {[0] = "Grey"}},
            [83] = {name = "Mesh Jersey", colors = {[0] = "Red/White"}},
            [84] = {name = "Zip-Up Sweater", colors = {[0] = "Navy"}},
            [85] = {name = "Light Hoodie", colors = {[0] = "Grey"}},
            [86] = {name = "Flannel Zip", colors = {[0] = "Blue/Black"}},
            [87] = {name = "Work Overalls", colors = {[0] = "Blue"}},
            [88] = {name = "Mechanic Shirt", colors = {[0] = "Blue/Orange"}},
            [89] = {name = "Sweater Vest", colors = {[0] = "Grey"}},
            [90] = {name = "Sleeve Hoodie", colors = {[0] = "Black"}},
            [91] = {name = "Layered Tee", colors = {[0] = "White/Black"}},
            [92] = {name = "Satin Jacket", colors = {[0] = "Black/Red"}},
            [93] = {name = "Corduroy Shirt", colors = {[0] = "Brown"}},
            [94] = {name = "T-Shirt w/ Logo", colors = {[0] = "White/Black"}},
            [95] = {name = "Sleeveless Tee w/ Pattern", colors = {[0] = "Camo"}},
            [96] = {name = "Polka Dot Shirt", colors = {[0] = "Red/White"}},
            [97] = {name = "Printed Hoodie", colors = {[0] = "Black/Grey"}},
            [98] = {name = "Ripped Tee", colors = {[0] = "Black"}},
            [99] = {name = "Fun Shirt", colors = {[0] = "Cartoon Print"}},
            [100] = {name = "Denim Tank", colors = {[0] = "Blue"}},
            [101] = {name = "Tie-Dye Shirt", colors = {[0] = "Multicolor"}},
            [102] = {
                name = "Painter’s Shirt",
                colors = {[0] = "Paint Splatter"}
            },
            [103] = {name = "Festival Vest", colors = {[0] = "Neon"}},
            [104] = {name = "Cargo Top", colors = {[0] = "Olive"}},
            [105] = {name = "Safety Vest Shirt", colors = {[0] = "Yellow"}},
            [106] = {name = "Athletic Tank", colors = {[0] = "Grey"}},
            [107] = {name = "Motorcycle Hoodie", colors = {[0] = "Black"}},
            [108] = {name = "Work Tee", colors = {[0] = "Orange"}},
            [109] = {name = "Construction Vest", colors = {[0] = "Yellow"}},
            [110] = {name = "Flag Tee", colors = {[0] = "USA Flag"}},
            [111] = {name = "Graphic Tank", colors = {[0] = "White/Black"}},
            [112] = {name = "Fitted Tee", colors = {[0] = "Grey"}},
            [113] = {name = "Mesh Hoodie", colors = {[0] = "Black"}},
            [114] = {name = "Quilted Jacket", colors = {[0] = "Black"}},
            [115] = {name = "Utility Vest", colors = {[0] = "Olive"}},
            [116] = {name = "Work Shirt w/ Logo", colors = {[0] = "Blue/White"}},
            [117] = {name = "Tourist Shirt", colors = {[0] = "Hawaiian Print"}},
            [118] = {name = "Polo w/ Logo", colors = {[0] = "White/Black"}},
            [119] = {name = "Sports Jersey", colors = {[0] = "Red/White"}},
            [120] = {name = "Letterman Jacket", colors = {[0] = "Black/White"}},
            [121] = {name = "Varsity Hoodie", colors = {[0] = "White/Black"}},
            [122] = {name = "Work Overall", colors = {[0] = "Blue"}},
            [123] = {
                name = "Painter’s Overalls",
                colors = {[0] = "Paint Splatter"}
            },
            [124] = {name = "Chef’s Jacket", colors = {[0] = "White"}},
            [125] = {name = "Lab Coat", colors = {[0] = "White"}},
            [126] = {name = "Chef’s Apron", colors = {[0] = "White"}},
            [127] = {name = "Doctor’s Scrubs", colors = {[0] = "Green"}},
            [128] = {name = "Paramedic Shirt", colors = {[0] = "White/Red"}},
            [129] = {name = "Police Shirt", colors = {[0] = "Blue/Gold"}},
            [130] = {name = "Firefighter Top", colors = {[0] = "Yellow/Black"}},
            [131] = {name = "Construction Shirt", colors = {[0] = "Orange"}},
            [132] = {name = "Mechanic Shirt", colors = {[0] = "Blue/Orange"}}
        },

        -- ======================
        -- TORSOS (component 3)
        -- ======================
        torso = {
            [0] = {name = "None", colors = {[0] = "None"}},
            [1] = {name = "Vest", colors = {[0] = "Black"}},
            [2] = {name = "Cut-Off Vest", colors = {[0] = "Blue"}},
            [3] = {name = "Zip-Up Vest", colors = {[0] = "Grey"}},
            [4] = {name = "Hawaiian Vest", colors = {[0] = "Red/White"}},
            [5] = {
                name = "Leather Jacket",
                colors = {[0] = "Black", [1] = "Brown"}
            },
            [6] = {
                name = "Denim Jacket",
                colors = {[0] = "Blue", [1] = "Light Blue"}
            },
            [7] = {
                name = "Bomber Jacket",
                colors = {[0] = "Black", [1] = "Green"}
            },
            [8] = {
                name = "Track Jacket",
                colors = {[0] = "Red/Black", [1] = "Blue/White"}
            },
            [9] = {
                name = "Varsity Jacket",
                colors = {[0] = "Black/White", [1] = "Blue/White"}
            },
            [10] = {
                name = "Rain Jacket",
                colors = {[0] = "Yellow", [1] = "Orange"}
            },
            [11] = {
                name = "Puffer Jacket",
                colors = {[0] = "Black", [1] = "Olive"}
            },
            [12] = {name = "Jean Jacket", colors = {[0] = "Blue"}},
            [13] = {
                name = "Windbreaker",
                colors = {[0] = "Green", [1] = "Blue"}
            },
            [14] = {
                name = "Canvas Jacket",
                colors = {[0] = "Khaki", [1] = "Olive"}
            },
            [15] = {name = "Army Jacket", colors = {[0] = "Forest Camo"}},
            [16] = {name = "Leather Vest", colors = {[0] = "Black"}},
            [17] = {name = "Denim Vest", colors = {[0] = "Blue"}},
            [18] = {name = "Hooded Jacket", colors = {[0] = "Grey"}},
            [19] = {name = "Mesh Jacket", colors = {[0] = "Black"}},
            [20] = {name = "Blazer", colors = {[0] = "Black", [1] = "Navy"}},
            [21] = {name = "Blazer w/ Pattern", colors = {[0] = "Plaid"}},
            [22] = {name = "Sport Jacket", colors = {[0] = "Blue"}},
            [23] = {name = "Denim Overshirt", colors = {[0] = "Blue"}},
            [24] = {name = "Bike Jacket", colors = {[0] = "Black"}},
            [25] = {name = "Flight Jacket", colors = {[0] = "Green"}},
            [26] = {name = "Varsity Sweater", colors = {[0] = "Black/White"}},
            [27] = {name = "City Coat", colors = {[0] = "Black"}},
            [28] = {name = "Trench Coat", colors = {[0] = "Beige"}},
            [29] = {name = "Rain Coat", colors = {[0] = "Yellow"}},
            [30] = {name = "Leather Coat", colors = {[0] = "Black"}},
            [31] = {name = "Fur Vest", colors = {[0] = "Brown"}},
            [32] = {name = "Work Vest", colors = {[0] = "Orange"}},
            [33] = {name = "Reflective Jacket", colors = {[0] = "Yellow"}},
            [34] = {name = "Moto Jacket", colors = {[0] = "Black"}},
            [35] = {name = "Racing Jacket", colors = {[0] = "Red/White"}},
            [36] = {name = "Lab Coat", colors = {[0] = "White"}},
            [37] = {name = "Construction Vest", colors = {[0] = "Yellow"}},
            [38] = {name = "Paramedic Vest", colors = {[0] = "White/Red"}},
            [39] = {name = "Police Jacket", colors = {[0] = "Navy/Gold"}},
            [40] = {name = "Firefighter Coat", colors = {[0] = "Yellow/Black"}},
            [41] = {name = "Chef’s Coat", colors = {[0] = "White"}},
            [42] = {name = "Doctor’s Coat", colors = {[0] = "White"}},
            [43] = {name = "Mechanic Jacket", colors = {[0] = "Blue/Orange"}},
            [44] = {name = "Delivery Vest", colors = {[0] = "Green/White"}},
            [45] = {name = "Sports Hoodie", colors = {[0] = "Red/White"}},
            [46] = {name = "Motorcycle Vest", colors = {[0] = "Black"}},
            [47] = {name = "Bulletproof Vest", colors = {[0] = "Black"}},
            [48] = {name = "Police Tactical Vest", colors = {[0] = "Black"}},
            [49] = {name = "SWAT Jacket", colors = {[0] = "Black"}},
            [50] = {name = "Detective Jacket", colors = {[0] = "Grey"}},
            [51] = {name = "Hockey Jersey", colors = {[0] = "Red/White"}},
            [52] = {name = "Baseball Jacket", colors = {[0] = "Blue/White"}},
            [53] = {name = "Cowboy Vest", colors = {[0] = "Brown"}},
            [54] = {name = "Denim Cooper", colors = {[0] = "Blue"}},
            [55] = {name = "Canvas Vest", colors = {[0] = "Olive"}},
            [56] = {name = "Quilted Vest", colors = {[0] = "Black"}},
            [57] = {name = "Poncho", colors = {[0] = "Red/Yellow"}},
            [58] = {name = "Poncho Blue", colors = {[0] = "Blue/White"}},
            [59] = {name = "Suit Jacket", colors = {[0] = "Black"}},
            [60] = {name = "Double Breasted Coat", colors = {[0] = "Black"}},
            [61] = {name = "Trench Coat Dark", colors = {[0] = "Black"}},
            [62] = {name = "Rain Poncho", colors = {[0] = "Yellow"}},
            [63] = {name = "Duster Coat", colors = {[0] = "Brown"}},
            [64] = {name = "Lab Jacket", colors = {[0] = "White"}},
            [65] = {name = "School Blazer", colors = {[0] = "Blue"}},
            [66] = {name = "Field Jacket", colors = {[0] = "Olive"}},
            [67] = {name = "Bike Armor Vest", colors = {[0] = "Black"}},
            [68] = {name = "Ski Jacket", colors = {[0] = "Orange/White"}},
            [69] = {name = "Snow Parka", colors = {[0] = "White/Blue"}},
            [70] = {name = "Forest Camo Jacket", colors = {[0] = "Camo"}},
            [71] = {name = "Urban Camo Jacket", colors = {[0] = "Camo"}}
        },

        -- ======================
        -- PANTS (component 4)
        -- ======================
        pants = {
            [0] = {
                name = "Jeans",
                colors = {[0] = "Blue", [1] = "Black", [2] = "Grey"}
            },
            [1] = {
                name = "Shorts",
                colors = {[0] = "Red", [1] = "White", [2] = "Black"}
            },
            [2] = {
                name = "Cargo Pants",
                colors = {[0] = "Khaki", [1] = "Olive"}
            },
            [3] = {name = "Sweatpants", colors = {[0] = "Grey", [1] = "Black"}},
            [4] = {name = "Chinos", colors = {[0] = "Khaki", [1] = "Navy"}},
            [5] = {name = "Leather Pants", colors = {[0] = "Black"}},
            [6] = {
                name = "Dress Pants",
                colors = {[0] = "Black", [1] = "Grey", [2] = "Navy"}
            },
            [7] = {
                name = "Track Pants",
                colors = {[0] = "Black/White", [1] = "Blue/White"}
            },
            [8] = {name = "Joggers", colors = {[0] = "Grey", [1] = "Black"}},
            [9] = {name = "Khaki Pants", colors = {[0] = "Khaki"}},
            [10] = {name = "Camo Pants", colors = {[0] = "Forest"}},
            [11] = {name = "Denim Pants", colors = {[0] = "Blue"}},
            [12] = {name = "Biker Pants", colors = {[0] = "Black"}},
            [13] = {name = "Motorcycle Chaps", colors = {[0] = "Black"}},
            [14] = {name = "Ghillie Pants", colors = {[0] = "Forest Camo"}},
            [15] = {name = "Lab Pants", colors = {[0] = "White"}},
            [16] = {name = "Chef Pants", colors = {[0] = "White"}},
            [17] = {name = "Paramedic Pants", colors = {[0] = "White/Red"}},
            [18] = {name = "Police Pants", colors = {[0] = "Navy"}},
            [19] = {name = "Firefighter Pants", colors = {[0] = "Black"}},
            [20] = {name = "Construction Pants", colors = {[0] = "Khaki"}},
            [21] = {
                name = "Business Slacks",
                colors = {[0] = "Black", [1] = "Grey"}
            },
            [22] = {name = "Beach Shorts", colors = {[0] = "Floral"}},
            [23] = {name = "Swim Trunks", colors = {[0] = "Blue"}},
            [24] = {name = "Cargo Shorts", colors = {[0] = "Olive"}},
            [25] = {name = "Denim Shorts", colors = {[0] = "Blue"}},
            [26] = {name = "Military Pants", colors = {[0] = "Camo"}},
            [27] = {name = "Track Shorts", colors = {[0] = "Black/White"}},
            [28] = {name = "Gym Shorts", colors = {[0] = "Grey"}},
            [29] = {name = "Board Shorts", colors = {[0] = "Green"}},
            [30] = {
                name = "Painter’s Pants",
                colors = {[0] = "Paint Splatter"}
            },
            [31] = {name = "Doc Scrubs Pants", colors = {[0] = "Green"}},
            [32] = {name = "Mechanic Overalls", colors = {[0] = "Blue"}},
            [33] = {name = "Work Pants", colors = {[0] = "Tan"}},
            [34] = {name = "Sports Shorts", colors = {[0] = "Red/White"}},
            [35] = {name = "College Pants", colors = {[0] = "Black"}},
            [36] = {name = "Cowboy Chaps", colors = {[0] = "Brown"}},
            [37] = {name = "Denim Overalls", colors = {[0] = "Blue"}},
            [38] = {name = "Cargo Overalls", colors = {[0] = "Khaki"}},
            [39] = {name = "Lab Overalls", colors = {[0] = "White"}},
            [40] = {name = "Paramedic Overalls", colors = {[0] = "White/Red"}},
            [41] = {name = "Police Overalls", colors = {[0] = "Navy"}},
            [42] = {
                name = "Firefighter Overalls",
                colors = {[0] = "Yellow/Black"}
            },
            [43] = {name = "Chef Overalls", colors = {[0] = "White"}},
            [44] = {name = "Lab Coat Pants", colors = {[0] = "White"}},
            [45] = {name = "Pajama Pants", colors = {[0] = "Blue/White"}},
            [46] = {name = "Jogging Pants", colors = {[0] = "Black"}},
            [47] = {name = "Tactical Pants", colors = {[0] = "Black"}},
            [48] = {name = "Ski Pants", colors = {[0] = "Black/Orange"}},
            [49] = {name = "Snow Pants", colors = {[0] = "White/Blue"}},
            [50] = {name = "Ghillie Overalls", colors = {[0] = "Forest Camo"}},
            [51] = {name = "Cartel Pants", colors = {[0] = "Black/Red"}},
            [52] = {name = "Streetwear Pants", colors = {[0] = "Black/Gold"}},
            [53] = {name = "Denim Track Pants", colors = {[0] = "Blue/White"}},
            [54] = {name = "Cargo Dress Pants", colors = {[0] = "Khaki"}},
            [55] = {name = "Police SWAT Pants", colors = {[0] = "Black"}},
            [56] = {name = "Fire SWAT Pants", colors = {[0] = "Black"}},
            [57] = {name = "Military Overalls", colors = {[0] = "Camo"}},
            [58] = {name = "Racing Pants", colors = {[0] = "Red/White"}},
            [59] = {name = "Mechanic Pants", colors = {[0] = "Blue/Orange"}},
            [60] = {name = "Referee Shorts", colors = {[0] = "Black/White"}},
            [61] = {name = "Chef Pants w/ Apron", colors = {[0] = "White"}},
            [62] = {name = "Doctor’s Scrub Pants", colors = {[0] = "Green"}},
            [63] = {
                name = "Paramedic Scrub Pants",
                colors = {[0] = "White/Red"}
            },
            [64] = {name = "Police Duty Pants", colors = {[0] = "Navy"}},
            [65] = {
                name = "Firefighter Duty Pants",
                colors = {[0] = "Yellow/Black"}
            },
            [66] = {
                name = "Construction Pants w/ Reflective",
                colors = {[0] = "Yellow"}
            },
            [67] = {name = "Business Casual Pants", colors = {[0] = "Grey"}},
            [68] = {name = "Denim Overalls Cargo", colors = {[0] = "Blue"}},
            [69] = {name = "Track Suit Bottoms", colors = {[0] = "Red/Black"}},
            [70] = {name = "Cargo Snow Pants", colors = {[0] = "White/Blue"}},
            [71] = {
                name = "Ghillie Pants Desert",
                colors = {[0] = "Desert Camo"}
            }
        },

        shoes = {
            [0] = {
                name = "Sneakers",
                colors = {
                    [0] = "White",
                    [1] = "Black",
                    [2] = "Red",
                    [3] = "Blue"
                }
            },
            [1] = {name = "Loafers", colors = {[0] = "Brown", [1] = "Black"}},
            [2] = {
                name = "Boots",
                colors = {[0] = "Brown", [1] = "Black", [2] = "Tan"}
            },
            [3] = {name = "Sandals", colors = {[0] = "Tan", [1] = "Blue"}},
            [4] = {
                name = "Dress Shoes",
                colors = {[0] = "Black", [1] = "Brown"}
            },
            [5] = {name = "Slides", colors = {[0] = "Black", [1] = "Blue"}},
            [6] = {name = "Heels", colors = {[0] = "Black", [1] = "Red"}},
            [7] = {
                name = "Athletic Shoes",
                colors = {[0] = "White", [1] = "Black", [2] = "Grey"}
            },
            [8] = {name = "High Tops", colors = {[0] = "White", [1] = "Black"}},
            [9] = {name = "Work Boots", colors = {[0] = "Brown", [1] = "Tan"}},
            [10] = {name = "Motorcycle Boots", colors = {[0] = "Black"}},
            [11] = {name = "Snow Boots", colors = {[0] = "White/Black"}},
            [12] = {name = "Dress Boots", colors = {[0] = "Black"}},
            [13] = {name = "Sandals w/ Socks", colors = {[0] = "White/Black"}},
            [14] = {name = "Canvas Shoes", colors = {[0] = "Red", [1] = "Blue"}},
            [15] = {name = "Court Shoes", colors = {[0] = "White/Red"}},
            [16] = {name = "Golf Shoes", colors = {[0] = "White"}},
            [17] = {name = "Field Boots", colors = {[0] = "Brown"}},
            [18] = {name = "SWAT Boots", colors = {[0] = "Black"}},
            [19] = {name = "Fire Boots", colors = {[0] = "Black"}},
            [20] = {name = "Paramedic Shoes", colors = {[0] = "White"}},
            [21] = {name = "Police Boots", colors = {[0] = "Black"}},
            [22] = {name = "Construction Boots", colors = {[0] = "Brown"}},
            [23] = {name = "Climbing Shoes", colors = {[0] = "Black"}},
            [24] = {name = "Beach Flip Flops", colors = {[0] = "Black/White"}},
            [25] = {name = "Tennis Shoes", colors = {[0] = "White/Blue"}},
            [26] = {name = "High Heel Boots", colors = {[0] = "Black"}},
            [27] = {name = "Driving Loafers", colors = {[0] = "Brown"}},
            [28] = {name = "Slip-On Shoes", colors = {[0] = "Black"}},
            [29] = {name = "Dress Sandals", colors = {[0] = "Brown"}},
            [30] = {name = "Chef's NonSlip", colors = {[0] = "Black"}},
            [31] = {name = "Surgeon’s Shoes", colors = {[0] = "White"}},
            [32] = {name = "Mechanic Shoes", colors = {[0] = "Black"}},
            [33] = {name = "Hiking Boots", colors = {[0] = "Brown"}},
            [34] = {name = "Dance Shoes", colors = {[0] = "Black"}},
            [35] = {name = "Police SWAT Boots", colors = {[0] = "Black"}},
            [36] = {name = "Fire SWAT Boots", colors = {[0] = "Black"}},
            [37] = {name = "Snow Parka Boots", colors = {[0] = "White/Black"}},
            [38] = {name = "Snow Winter Boots", colors = {[0] = "White/Blue"}},
            [39] = {name = "Military Boots", colors = {[0] = "Camo"}},
            [40] = {name = "Racing Shoes", colors = {[0] = "Red/White"}},
            [41] = {name = "Paramedic Boots", colors = {[0] = "White"}},
            [42] = {name = "Doctor’s Clogs", colors = {[0] = "White"}},
            [43] = {name = "Firefighter Boots", colors = {[0] = "Black"}},
            [44] = {
                name = "Construction Boots w/ Reflective",
                colors = {[0] = "Yellow/Black"}
            },
            [45] = {name = "Business Loafers", colors = {[0] = "Black"}},
            [46] = {name = "Dress Leather Shoes", colors = {[0] = "Brown"}},
            [47] = {name = "Slip Resistant Shoes", colors = {[0] = "Black"}},
            [48] = {name = "Motorcycle Pack Boots", colors = {[0] = "Black"}},
            [49] = {name = "Variety Trainer", colors = {[0] = "White/Black"}},
            [50] = {name = "Festival Boots", colors = {[0] = "Black/White"}},
            [51] = {name = "Designer Sneakers", colors = {[0] = "White/Gold"}},
            [52] = {name = "Casual Slip-Ons", colors = {[0] = "Grey"}},
            [53] = {name = "Canvas Flip Flops", colors = {[0] = "Black"}},
            [54] = {name = "Dancing Trainers", colors = {[0] = "Red/White"}},
            [55] = {name = "Flooring Slippers", colors = {[0] = "White"}},
            [56] = {name = "Tactical Boots", colors = {[0] = "Black"}},
            [57] = {name = "Snow Track Boots", colors = {[0] = "White/Blue"}},
            [58] = {name = "Hiking Trail Boots", colors = {[0] = "Brown/Green"}},
            [59] = {name = "Paramedic Slip-Ons", colors = {[0] = "White/Red"}},
            [60] = {name = "Chef's Anti-Fatigue", colors = {[0] = "Black"}},
            [61] = {name = "Mechanic Sneakers", colors = {[0] = "Black/Yellow"}},
            [62] = {name = "Dodge Trainer", colors = {[0] = "White/Red"}},
            [63] = {name = "Racing Boots", colors = {[0] = "Red/White"}},
            [64] = {name = "Police Rally Boots", colors = {[0] = "Black/Blue"}},
            [65] = {name = "Fire Rally Boots", colors = {[0] = "Black/Yellow"}},
            [66] = {
                name = "Hiker’s Snow Boots",
                colors = {[0] = "White/Green"}
            },
            [67] = {
                name = "Beach Flip-Flops w/ Logo",
                colors = {[0] = "White/Green"}
            },
            [68] = {name = "Surfing Sandals", colors = {[0] = "Blue/White"}},
            [69] = {name = "Designer Loafers", colors = {[0] = "Black/Gold"}},
            [70] = {name = "Comfy Slippers", colors = {[0] = "Grey"}},
            [71] = {name = "Chef's Slip-Resistant", colors = {[0] = "Black"}},
            [72] = {name = "Gym Trainers", colors = {[0] = "White/Red"}},
            [73] = {name = "Workout Shoes", colors = {[0] = "Grey/Blue"}},
            [74] = {name = "Dance Platform Shoes", colors = {[0] = "Black"}},
            [75] = {
                name = "Designer Dress Shoes",
                colors = {[0] = "Black/White"}
            },
            [76] = {name = "Luxury Loafers", colors = {[0] = "Brown/Gold"}},
            [77] = {name = "Moto Racer Boots", colors = {[0] = "Black/Red"}},
            [78] = {name = "Race Day Sneakers", colors = {[0] = "White/Green"}},
            [79] = {name = "Festival Sandals", colors = {[0] = "Neon"}},
            [80] = {name = "Tactical Ankle Boots", colors = {[0] = "Black"}},
            [81] = {name = "Snow Hiker Boots", colors = {[0] = "White/Black"}},
            [82] = {
                name = "Paramedic Rally Shoes",
                colors = {[0] = "White/Red"}
            },
            [83] = {name = "Doctor’s Slip-Ons", colors = {[0] = "White"}},
            [84] = {name = "Denim Casual Shoes", colors = {[0] = "Blue"}},
            [85] = {name = "Canvas Low Tops", colors = {[0] = "White"}},
            [86] = {name = "Basketball Shoes", colors = {[0] = "White/Red"}},
            [87] = {name = "Soccer Cleats", colors = {[0] = "White/Blue"}},
            [88] = {name = "Tennis Trainers", colors = {[0] = "White/Green"}},
            [89] = {name = "Golf Trainers", colors = {[0] = "White/Black"}},
            [90] = {name = "Cycling Shoes", colors = {[0] = "Black/Yellow"}},
            [91] = {name = "Chef’s Comfortable", colors = {[0] = "Black"}},
            [92] = {
                name = "Mechanic Rally Shoes",
                colors = {[0] = "Black/Yellow"}
            },
            [93] = {
                name = "Beach Strappy Sandals",
                colors = {[0] = "White/Blue"}
            },
            [94] = {name = "Streetwear Boots", colors = {[0] = "Black/White"}},
            [95] = {name = "Designer Slip-Ons", colors = {[0] = "Black/Gold"}},
            [96] = {
                name = "Hiking Trail Sneakers",
                colors = {[0] = "Green/Black"}
            },
            [97] = {
                name = "Lightweight Sports Shoes",
                colors = {[0] = "White/Blue"}
            },
            [98] = {name = "Workout Slip-Ons", colors = {[0] = "Black/White"}},
            [99] = {name = "Festival Trainers", colors = {[0] = "Neon"}},
            [100] = {name = "Luxury Dress Shoes", colors = {[0] = "Black/Gold"}},
            [101] = {name = "Moto Racing Boots", colors = {[0] = "Black/Red"}},
            [102] = {
                name = "Racing Day Trainers",
                colors = {[0] = "White/Green"}
            },
            [103] = {name = "Comfy Flip-Flops", colors = {[0] = "Grey"}},
            [104] = {
                name = "Paramedic Street Shoes",
                colors = {[0] = "White/Red"}
            },
            [105] = {
                name = "Doctor’s Running Shoes",
                colors = {[0] = "White/Green"}
            },
            [106] = {name = "Snow Sport Boots", colors = {[0] = "White/Blue"}},
            [107] = {name = "Military Tactical Boots", colors = {[0] = "Camo"}},
            [108] = {name = "Dance Trainers", colors = {[0] = "Black"}},
            [109] = {
                name = "Designer Sport Shoes",
                colors = {[0] = "White/Gold"}
            },
            [110] = {name = "Canvas Festival Shoes", colors = {[0] = "Neon"}},
            [111] = {name = "Comfy House Slippers", colors = {[0] = "Grey"}},
            [112] = {
                name = "Chef’s Slip-Resistant Pro",
                colors = {[0] = "Black"}
            },
            [113] = {
                name = "Mechanic Work Boots Pro",
                colors = {[0] = "Black/Yellow"}
            },
            [114] = {name = "Beach Pool Slides", colors = {[0] = "White/Blue"}},
            [115] = {
                name = "Streetwear Slip-Ons",
                colors = {[0] = "Black/White"}
            },
            [116] = {name = "Moto Club Boots", colors = {[0] = "Black/Red"}},
            [117] = {
                name = "Racing Track Trainers",
                colors = {[0] = "White/Green"}
            },
            [118] = {
                name = "Designer Running Shoes",
                colors = {[0] = "White/Gold"}
            },
            [119] = {name = "Festival Combat Boots", colors = {[0] = "Neon"}},
            [120] = {name = "Luxury High Tops", colors = {[0] = "White/Gold"}},
            [121] = {
                name = "Paramedic Professional Boots",
                colors = {[0] = "White/Red"}
            },
            [122] = {
                name = "Doctor’s Athletic Trainers",
                colors = {[0] = "White/Green"}
            },
            [123] = {name = "Snow Alpine Boots", colors = {[0] = "White/Blue"}},
            [124] = {name = "Military Field Boots", colors = {[0] = "Camo"}},
            [125] = {name = "Dance Heels (High)", colors = {[0] = "Black"}},
            [126] = {
                name = "Designer Ballet Flats",
                colors = {[0] = "Black/Gold"}
            },
            [127] = {name = "Canvas Loafers", colors = {[0] = "White"}},
            [128] = {name = "Comfy House Sneakers", colors = {[0] = "Grey"}},
            [129] = {
                name = "Chef’s Slip-Resistant Extreme",
                colors = {[0] = "Black"}
            },
            [130] = {
                name = "Mechanic Pro Work Boots",
                colors = {[0] = "Black/Yellow"}
            },
            [131] = {
                name = "Beach Flip-Flop w/ Logo Pro",
                colors = {[0] = "White/Blue"}
            },
            [132] = {
                name = "Streetwear Competition Shoes",
                colors = {[0] = "Black/White"}
            },
            [133] = {
                name = "Moto Pro Racing Boots",
                colors = {[0] = "Black/Red"}
            },
            [134] = {
                name = "Racing Enduro Boots",
                colors = {[0] = "White/Green"}
            },
            [135] = {
                name = "Designer Ultra-Running Shoes",
                colors = {[0] = "White/Gold"}
            },
            [136] = {name = "Festival LED Trainers", colors = {[0] = "Neon"}},
            [137] = {
                name = "Luxury High Top Pro",
                colors = {[0] = "White/Gold"}
            },
            [138] = {
                name = "Paramedic Ultra Safe Boots",
                colors = {[0] = "White/Red"}
            },
            [139] = {
                name = "Doctor’s Marathon Trainers",
                colors = {[0] = "White/Green"}
            },
            [140] = {
                name = "Snow Expedition Boots",
                colors = {[0] = "White/Blue"}
            },
            [141] = {name = "Military Stealth Boots", colors = {[0] = "Camo"}},
            [142] = {name = "Dance Platform Retro", colors = {[0] = "Black"}},
            [143] = {
                name = "Designer Knit Sneakers",
                colors = {[0] = "White/Gold"}
            },
            [144] = {name = "Canvas Slip-On Festival", colors = {[0] = "Neon"}},
            [145] = {name = "Comfy House Slipper Pro", colors = {[0] = "Grey"}},
            [146] = {
                name = "Chef’s Slip-Resistant Elite",
                colors = {[0] = "Black"}
            },
            [147] = {
                name = "Mechanic Rally Racing Boots",
                colors = {[0] = "Black/Yellow"}
            },
            [148] = {
                name = "Beach Surf Slip-Ons",
                colors = {[0] = "White/Blue"}
            },
            [149] = {
                name = "Streetwear Hybrid Trainers",
                colors = {[0] = "Black/White"}
            },
            [150] = {
                name = "Moto Rally Race Boots",
                colors = {[0] = "Black/Red"}
            },
            [151] = {
                name = "Racing Enduro Trainers",
                colors = {[0] = "White/Green"}
            },
            [152] = {
                name = "Designer Tech Trainers",
                colors = {[0] = "White/Gold"}
            },
            [153] = {name = "Festival Glow Trainers", colors = {[0] = "Neon"}},
            [154] = {name = "Luxury Slip-On Pro", colors = {[0] = "White/Gold"}},
            [155] = {
                name = "Paramedic Apex Boots",
                colors = {[0] = "White/Red"}
            },
            [156] = {
                name = "Doctor’s Marathon Pro",
                colors = {[0] = "White/Green"}
            },
            [157] = {name = "Snow Arctic Boots", colors = {[0] = "White/Blue"}},
            [158] = {name = "Military Recon Boots", colors = {[0] = "Camo"}},
            [159] = {name = "Dance Retro High Tops", colors = {[0] = "Black"}},
            [160] = {
                name = "Designer City Sneakers",
                colors = {[0] = "White/Gold"}
            },
            [161] = {name = "Canvas Street Loafers", colors = {[0] = "Neon"}},
            [162] = {name = "Comfy Indoor Slippers", colors = {[0] = "Grey"}},
            [163] = {
                name = "Chef’s Ultra Slip-Resistant",
                colors = {[0] = "Black"}
            },
            [164] = {
                name = "Mechanic Performance Boots",
                colors = {[0] = "Black/Yellow"}
            },
            [165] = {name = "Beach Pro Sandals", colors = {[0] = "White/Blue"}},
            [166] = {
                name = "Streetwear Retro Runners",
                colors = {[0] = "Black/White"}
            },
            [167] = {
                name = "Moto Elite Racing Boots",
                colors = {[0] = "Black/Red"}
            },
            [168] = {
                name = "Racing Enduro Elite Trainers",
                colors = {[0] = "White/Green"}
            },
            [169] = {
                name = "Designer Future Sneakers",
                colors = {[0] = "White/Gold"}
            },
            [170] = {
                name = "Festival Ultimate Trainers",
                colors = {[0] = "Neon"}
            },
            [171] = {
                name = "Luxury Urban Slip-Ons",
                colors = {[0] = "White/Gold"}
            },
            [172] = {
                name = "Paramedic Ultra Boots",
                colors = {[0] = "White/Red"}
            },
            [173] = {
                name = "Doctor’s Marathon Elite",
                colors = {[0] = "White/Green"}
            },
            [174] = {name = "Snow Extreme Boots", colors = {[0] = "White/Blue"}},
            [175] = {name = "Military Stealth Elite", colors = {[0] = "Camo"}},
            [176] = {name = "Dance Neon High Tops", colors = {[0] = "Black"}},
            [177] = {
                name = "Designer Carbon Sneakers",
                colors = {[0] = "White/Gold"}
            },
            [178] = {name = "Canvas Ultra Slip-Ons", colors = {[0] = "Neon"}},
            [179] = {name = "Comfy Thermo Slippers", colors = {[0] = "Grey"}},
            [180] = {
                name = "Chef’s Ultra Elite Slip-Resistant",
                colors = {[0] = "Black"}
            },
            [181] = {
                name = "Mechanic Rally Performance Boots",
                colors = {[0] = "Black/Yellow"}
            },
            [182] = {
                name = "Beach Ultra Pro Sandals",
                colors = {[0] = "White/Blue"}
            },
            [183] = {
                name = "Streetwear Performance Trainers",
                colors = {[0] = "Black/White"}
            },
            [184] = {
                name = "Moto Hyper Racing Boots",
                colors = {[0] = "Black/Red"}
            },
            [185] = {
                name = "Racing Enduro Hyper Trainers",
                colors = {[0] = "White/Green"}
            },
            [186] = {
                name = "Designer Carbon Pro Sneakers",
                colors = {[0] = "White/Gold"}
            },
            [187] = {name = "Festival Hyper Trainers", colors = {[0] = "Neon"}},
            [188] = {
                name = "Luxury Carbon Slip-Ons",
                colors = {[0] = "White/Gold"}
            },
            [189] = {
                name = "Paramedic Ultra Elite Boots",
                colors = {[0] = "White/Red"}
            },
            [190] = {
                name = "Doctor’s Marathon Hyper",
                colors = {[0] = "White/Green"}
            },
            [191] = {
                name = "Snow Extreme Pro Boots",
                colors = {[0] = "White/Blue"}
            },
            [192] = {name = "Military Stealth Ultra", colors = {[0] = "Camo"}},
            [193] = {
                name = "Dance Neon Elite High Tops",
                colors = {[0] = "Black"}
            },
            [194] = {
                name = "Designer Quantum Sneakers",
                colors = {[0] = "White/Gold"}
            },
            [195] = {
                name = "Canvas Ultra Hyper Slip-Ons",
                colors = {[0] = "Neon"}
            },
            [196] = {
                name = "Comfy Thermo Hyper Slippers",
                colors = {[0] = "Grey"}
            },
            [197] = {
                name = "Chef’s Ultra Supreme Slip-Resistant",
                colors = {[0] = "Black"}
            },
            [198] = {
                name = "Mechanic Rally Supreme Boots",
                colors = {[0] = "Black/Yellow"}
            },
            [199] = {
                name = "Beach Ultra Supreme Sandals",
                colors = {[0] = "White/Blue"}
            },
            [200] = {
                name = "Streetwear Performance Elite Trainers",
                colors = {[0] = "Black/White"}
            },
            [201] = {
                name = "Moto Hyper Elite Racing Boots",
                colors = {[0] = "Black/Red"}
            },
            [202] = {
                name = "Racing Enduro Ultra Trainers",
                colors = {[0] = "White/Green"}
            },
            [203] = {
                name = "Designer Quantum Pro Sneakers",
                colors = {[0] = "White/Gold"}
            },
            [204] = {
                name = "Festival Hyper Elite Trainers",
                colors = {[0] = "Neon"}
            },
            [205] = {
                name = "Luxury Carbon Supreme Slip-Ons",
                colors = {[0] = "White/Gold"}
            },
            [206] = {
                name = "Paramedic Ultra Hyper Boots",
                colors = {[0] = "White/Red"}
            },
            [207] = {
                name = "Doctor’s Marathon Supreme",
                colors = {[0] = "White/Green"}
            },
            [208] = {
                name = "Snow Extreme Hyper Boots",
                colors = {[0] = "White/Blue"}
            },
            [209] = {name = "Military Stealth Supreme", colors = {[0] = "Camo"}},
            [210] = {
                name = "Dance Neon Ultra High Tops",
                colors = {[0] = "Black"}
            },
            [211] = {
                name = "Designer Quantum Supreme Sneakers",
                colors = {[0] = "White/Gold"}
            },
            [212] = {
                name = "Canvas Ultra Hyper Elite Slip-Ons",
                colors = {[0] = "Neon"}
            },
            [213] = {
                name = "Comfy Thermo Hyper Elite Slippers",
                colors = {[0] = "Grey"}
            },
            [214] = {
                name = "Chef’s Ultra Supreme Pro Slip-Resistant",
                colors = {[0] = "Black"}
            },
            [215] = {
                name = "Mechanic Rally Supreme Performance Boots",
                colors = {[0] = "Black/Yellow"}
            },
            [216] = {
                name = "Beach Ultra Supreme Pro Sandals",
                colors = {[0] = "White/Blue"}
            },
            [217] = {
                name = "Streetwear Performance Ultra Trainers",
                colors = {[0] = "Black/White"}
            },
            [218] = {
                name = "Moto Hyper Elite Supreme Racing Boots",
                colors = {[0] = "Black/Red"}
            },
            [219] = {
                name = "Racing Enduro Ultra Hyper Trainers",
                colors = {[0] = "White/Green"}
            },
            [220] = {
                name = "Designer Quantum Supreme Pro Sneakers",
                colors = {[0] = "White/Gold"}
            }
        },

        fighting = {},
        hat = {
            [0] = {name = "None", colors = {[0] = "None"}},
            [1] = {
                name = "Baseball Cap",
                colors = {
                    [0] = "White",
                    [1] = "Black",
                    [2] = "Red",
                    [3] = "Blue",
                    [4] = "Green",
                    [5] = "Yellow"
                }
            },
            [2] = {name = "Driver Cap", colors = {[0] = "Black", [1] = "Brown"}},
            [3] = {
                name = "Fedora",
                colors = {[0] = "Black", [1] = "Grey", [2] = "Tan"}
            },
            [4] = {
                name = "Beanie",
                colors = {[0] = "Black", [1] = "Grey", [2] = "Red"}
            },
            [5] = {name = "Cowboy Hat", colors = {[0] = "Brown", [1] = "Black"}},
            [6] = {
                name = "Summer Fedora",
                colors = {[0] = "Beige", [1] = "White"}
            },
            [7] = {
                name = "Headphones Hat",
                colors = {[0] = "Black", [1] = "White"}
            },
            [8] = {name = "Puffball Hat", colors = {[0] = "Red", [1] = "Blue"}},
            [9] = {
                name = "Trucker Hat",
                colors = {[0] = "Black/White", [1] = "Blue/White"}
            },
            [10] = {name = "Skull Cap", colors = {[0] = "Black"}},
            [11] = {
                name = "Summer Hat",
                colors = {[0] = "Yellow", [1] = "Pink"}
            },
            [12] = {
                name = "Adventurer Hat",
                colors = {[0] = "Tan", [1] = "Brown"}
            },
            [13] = {name = "Flat Cap", colors = {[0] = "Grey", [1] = "Black"}},
            [14] = {
                name = "Panama Hat",
                colors = {[0] = "White", [1] = "Khaki"}
            },
            [15] = {name = "Chef Hat", colors = {[0] = "White"}},
            [16] = {name = "Top Hat", colors = {[0] = "Black"}},
            [17] = {name = "Panama Straw Hat", colors = {[0] = "Beige"}},
            [18] = {name = "Fedora (Dark)", colors = {[0] = "Dark Grey"}},
            [19] = {name = "Wide Brim Hat", colors = {[0] = "Black"}},
            [20] = {
                name = "Rasta Knit Cap",
                colors = {[0] = "Red/Yellow/Green"}
            },
            [21] = {name = "Police Hat", colors = {[0] = "Black"}},
            [22] = {name = "Sheriff Hat", colors = {[0] = "Tan"}},
            [23] = {name = "Sombrero", colors = {[0] = "Brown", [1] = "Black"}},
            [24] = {name = "Santa Hat", colors = {[0] = "Red/White"}},
            [25] = {name = "Vampire Hat", colors = {[0] = "Black"}},
            [26] = {name = "Wizard Hat", colors = {[0] = "Purple"}},
            [27] = {name = "Fisherman Hat", colors = {[0] = "Green"}},
            [28] = {name = "Bullhorn Hat", colors = {[0] = "Brown"}},
            [29] = {name = "Hockey Helmet", colors = {[0] = "White"}},
            [30] = {name = "Chef Hat (Blue)", colors = {[0] = "Blue"}},
            [31] = {name = "Boonie Hat", colors = {[0] = "Camo"}},
            [32] = {name = "Boonie Hat (Desert)", colors = {[0] = "Tan Camo"}},
            [33] = {name = "Bandana (Red)", colors = {[0] = "Red"}},
            [34] = {name = "Bandana (Blue)", colors = {[0] = "Blue"}},
            [35] = {name = "Bandana (Black)", colors = {[0] = "Black"}},
            [36] = {name = "Bandana (White)", colors = {[0] = "White"}},
            [37] = {name = "Bandana (Green)", colors = {[0] = "Green"}},
            [38] = {name = "Bandana (Orange)", colors = {[0] = "Orange"}},
            [39] = {name = "Bandana (Purple)", colors = {[0] = "Purple"}},
            [40] = {name = "Clown Hat", colors = {[0] = "Red/White"}},
            [41] = {name = "Clown Wig", colors = {[0] = "Rainbow"}},
            [42] = {name = "Cork Hat", colors = {[0] = "Brown"}},
            [43] = {name = "Construction Helmet", colors = {[0] = "Yellow"}},
            [44] = {name = "Fire Helmet", colors = {[0] = "Black/Yellow"}},
            [45] = {
                name = "Football Helmet",
                colors = {[0] = "Red/White", [1] = "Blue/White"}
            },
            [46] = {name = "Garrison Cap", colors = {[0] = "Green"}},
            [47] = {
                name = "Motorcycle Helmet",
                colors = {[0] = "Black", [1] = "Matte Black"}
            },
            [48] = {name = "Propeller Beanie", colors = {[0] = "Blue/Yellow"}},
            [49] = {name = "Visor (Clear)", colors = {[0] = "Clear"}},
            [50] = {name = "Visor (Blue)", colors = {[0] = "Blue"}},
            [51] = {name = "Visor (Red)", colors = {[0] = "Red"}},
            [52] = {name = "Yachting Cap", colors = {[0] = "White/Blue"}}
        }
    }
}

if config.enabled then Config.RegisterPluginConfig(config.pluginName, config) end
