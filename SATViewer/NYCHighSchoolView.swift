//
//  ContentView.swift
//  SATViewer
//
//  Created by Tyler Helmrich on 8/28/25.
//

import SwiftUI
import MapKit


/* MARK: FILE SETUP NOTE
 * I left all Models and ViewModels for this example app in this one file to make it easier to review.
 * Normally I would split models and view models into their own files and folders to make navigation and
 * structure clear in the side bar.
 */



// The SATScore Model is responsible for storing SAT data for a high school
struct SATScore: Decodable {
    var numTestTakers: Int
    var reading: Int
    var math: Int
    var writing: Int
    // the *ScoreQualityColorCode fields store a color depending on how well the school did in that SAT category
        // Red = Poor
        // Yellow = Average
        // Green = Good / Above Average
    var readingScoreQualityColorCode: Color
    var mathScoreQualityColorCode: Color
    var writingScoreQualityColorCode: Color

    // The CodingKeys enum maps JSON key names to the preferred name in the model
    enum CodingKeys: String, CodingKey {
        case numTestTakers = "num_of_sat_test_takers"
        case reading = "sat_critical_reading_avg_score"
        case math = "sat_math_avg_score"
        case writing = "sat_writing_avg_score"
    }
    
    // The Decoder init allows this model to be constructed from JSON Data
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        
        // Initialize the fields to all 0 before parsing
        // The all 0 identifier will also act as an error indicator
        // in the JSON data, schools that had no test takers mark these fields with "s" instead of 0
        numTestTakers = 0
        reading = 0
        math = 0
        writing = 0
        
        do {
            numTestTakers = Int(try container.decode(String.self, forKey: .numTestTakers)) ?? 0
            reading = Int(try container.decode(String.self, forKey: .reading)) ?? 0
            math = Int(try container.decode(String.self, forKey: .math)) ?? 0
            writing = Int(try container.decode(String.self, forKey: .writing)) ?? 0
        }
        catch {
            print(error.localizedDescription)
        }
        
        // The following operations set the color indicators based on the
        // thresholds defined below
        let goodScore = 650
        let avgScore = 450
        readingScoreQualityColorCode = reading > goodScore ? .green :
                        (reading > avgScore ? .yellow : .red)
        
        mathScoreQualityColorCode = math > goodScore ? .green :
                        (math > avgScore ? .yellow : .red)
        
        writingScoreQualityColorCode = writing > goodScore ? .green :
                        (writing > avgScore ? .yellow : .red)

    }
}

// The HighSchool Model stores information about an NYC High School
// The JSON spec for this API has many more fields available, but these are the ones
// I decided to use for this app
struct HighSchool: Decodable, Identifiable {
    var id: String {
        get {
            return dbn
        }
    }
    
    let dbn: String
    let schoolName: String
    let latitude: String?
    let longitude: String?
    let location: String
    
    // The CodingKeys map JSON key names to the peferred field names
    // No decoder init is required for this model as no custom decoding logic is required
    enum CodingKeys: String, CodingKey {
        case dbn = "dbn"
        case schoolName = "school_name"
        case latitude = "latitude"
        case longitude = "longitude"
        case location = "location"
    }
}

// The NYCHighSchoolViewModel is responsible for handling the Business logic of the application
// In this case that is fetching the list of High Schools and their SAT Scores using the API
// It also contains the observable highSchools field that the SwiftUI specific logic will react to
@Observable
class NYCHighSchoolViewModel {

    // Exposes the list of high schools to the UI for display
    var highSchools: [HighSchool]?
    
    
    // MARK: **For the sake of expediency** I've left URLs hardcoded to make the project easier to work with, ideally I would move these into environment files so they're not left hardcoded and are easier to change in  a hypothetical future scenario
    // MARK: **If I had more time** I would have liked to add a cacheing layer so that a school's SAT Data
    //    is fetched only the first time it's requested instead of every time
    // Loads the SAT Score for a high school given that school's dbn which is a
    // unique identifier for the school provided by the API
    func loadSATScore(for dbn: String) async -> SATScore? {
        
        // Constructs a URL from the base API url by appending the dbn
        // I'm preferring to append here rather than fetch all of the SAT Scores at the same time
        // in order to avoid pointless fetches
        guard let url = URL(string: "https://data.cityofnewyork.us/resource/f9bf-2cp4.json?dbn=\(dbn)") else {
            return nil
        }
        
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                print(response)
                throw URLError(.badServerResponse)
                
            }
            
            // The API always returns an array even if requesting a single result
            return try JSONDecoder().decode([SATScore].self, from: data).first
        }
        catch {
            // If an error occurs returns nil, **If I had more time** I would prefer to return a Result object
            // that the UI could react to and display more detailed error information to the user
            return nil
        }
    }
    
    // Loads the entire list of high schools and stores the result in the exposed highSchools field
    func loadHighSchools() async {
        // If an error occurs sets the highSchools field to an empty array,
        // MARK: **If I had more time** I would prefer to return a Result object that the UI could react to and display more detailed error information to the user
        guard let url = URL(string: "https://data.cityofnewyork.us/resource/s3k6-pzi2.json") else {
            highSchools = []
            return
        }
            
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                
                throw URLError(.badServerResponse)
                
            }
            
            highSchools = try JSONDecoder().decode([HighSchool].self, from: data)
            
        }
        catch {
            highSchools = []
        }
    }
}

struct NYCHighSchoolView: View {
    @State var loader = NYCHighSchoolViewModel()
    @State var displayHighSchoolDetails: HighSchool?
    @State var loadedScore: SATScore? = nil
    
    var body: some View {
        // Display a progress view while the list of high schools loads
        if loader.highSchools == nil {
            ProgressView {
                Text("Loading High Schools...")
            }
            .task {
                await loader.loadHighSchools()
            }
        }
        // In the case of an error or the API endpoint legitimately contains no data
        // inform the user here
        else if let highSchools = loader.highSchools, highSchools.isEmpty {
            Text("No High Schools Found...")
        }
        else {
            List {
                // Using a sectioned list to get a nice title above the list of high schools
                Section(header:
                    Text("NYC High Schools")
                    .font(.title)
                    .foregroundStyle(.black)
                    .bold()
                ) {
                    // The dbn is known to be unique from the API documentation so it can be used as the Id
                    // for the list
                    ForEach(loader.highSchools ?? [], id: \.dbn) { school in
                        Text(school.schoolName)
                        .onTapGesture {
                            // Tap will set the details which displays the sheet
                            displayHighSchoolDetails = school
                            // Task will then be kicked off to fetch the specific
                            // SAT Scores and display them in the sheet
                            Task {
                                guard let score = await self.loader.loadSATScore(for: school.dbn) else {
                                    return
                                }
                                
                                loadedScore = score
                            }
                        }
                    }
                }
            }
            .sheet(item: $displayHighSchoolDetails, content: { school in
                VStack(alignment: .center, spacing: 24) {
                    
                    Text(school.schoolName)
                        .font(.title)
                        .bold()
                        .padding([.leading, .top])

                    
                    if let loadedScore {
                        SATScoreReadout(loadedScore: loadedScore)
                    }
                    else {
                        ProgressView {
                            Text("Loading SAT Score Data...")
                        }
                    }
                    
                    Spacer()
                    
                    // Some Schools in the API don't provide longitude and latitude data so only
                    // display the map if it's avialable and an unavailable indicator otherwise
                    if let latitude = Double(school.latitude ?? ""),
                        let longitude = Double(school.longitude ?? "") {
                        
                        // Restrict the map to a height of 400 so it doesn't dominate the sheet
                        SchoolMap(latitude: latitude, longitude: longitude, schoolLocation: school.location)
                        .frame(height: 400)
                        
                    }
                    else {
                        
                        Text("Location Data Is Unavailable...")
                            .font(.headline)
                            .italic()
                            .foregroundStyle(.gray)
                        
                    }
                }
            })
        }
    }
}

extension NYCHighSchoolView {
    
    struct SATScoreReadout: View {
        let loadedScore: SATScore
        var body: some View {
            // As explained earlier in the SATScore Model not all schools have valid SAT data
            // so check for that here and display a data unavailable indicator instead
            if loadedScore.numTestTakers == 0 {
                Text("SAT Score Data Is Unavailable...")
                    .font(.headline)
                    .italic()
                    .foregroundStyle(.gray)
            }
            // Display a Horizontal list of SAT Scores above color coded boxes if data is available
            // An indicator of number of test takers at the school is shown below the HStack
            else {
                VStack(alignment: .center, spacing: 8) {
                    
                    HStack(spacing: 0) {
                        Spacer()
                        
                        SATScoreBox(categoryTitle: "Reading", scoreQualityColorCode: loadedScore.readingScoreQualityColorCode, score: loadedScore.reading)
                        
                        Spacer()
                        
                        SATScoreBox(categoryTitle: "Math", scoreQualityColorCode: loadedScore.mathScoreQualityColorCode, score: loadedScore.math)
                        
                        Spacer()
                        
                        SATScoreBox(categoryTitle: "Writing", scoreQualityColorCode: loadedScore.writingScoreQualityColorCode, score: loadedScore.writing)
                        
                        Spacer()
                    }
                    
                    // Text views take markdown **...** will turn the wrapped text bold
                    Text("Average Scores For **\(loadedScore.numTestTakers)** Test Takers")
                        .italic()
                }
            }
        }
    }
    
    // Score box shows the SAT Score for the category in white text above a
    // color quality indicator as explained in the SATScore Model
    struct SATScoreBox: View {
        let categoryTitle: String
        let scoreQualityColorCode: Color
        let score: Int
        
        var body: some View {
            VStack {
                Text(categoryTitle)
                    .font(.title2)
                    .fontWeight(.medium)
                    
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(scoreQualityColorCode)
                        .frame(width: 100, height: 100)
                    
                    Text("\(score)")
                        .font(.title2)
                        .fontWeight(.heavy)
                        .foregroundStyle(.white)
                }
            }
        }
    }
    
    
    // Display a Map of the schools location with the address as an annotation
    // build up from the latitude, longitude, and school's address as received from the API
    // the API calls the address the "location" because it appends the coordinates to the end of the address
    // MARK: **if I had more time** I would remove the coordinates from the location string but decided against of it for the scope of this project
    struct SchoolMap: View {
        let latitude: Double
        let longitude: Double
        let schoolLocation: String
        
        var body: some View {
            // defines a small region around the school's location for the map to draw
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
            )
            
            // This version of the Map API is deprecated in iOS 17 but it's the one I know
            // MARK: **given more time** I would learn and use the non-deprecated version
            Map(coordinateRegion: .constant(region), annotationItems: [SchoolMapMarker(location: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))]) { mapMarker in
                
                MapAnnotation(coordinate: mapMarker.location) {
                    VStack {
                        Text(schoolLocation)
                            .font(.caption)
                            .padding(4)
                            .background(Color.white.opacity(0.5))
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.red)
                            .font(.title)
                    }
                }
                
            }
        }
    }
    
    // Wrapping the coordinates of the school in this struct in order to make it identifiable for the annoation used by the Map above
    struct SchoolMapMarker: Identifiable {
        let id: UUID = UUID()
        let location: CLLocationCoordinate2D
    }
}

#Preview {
    NYCHighSchoolView()
}
