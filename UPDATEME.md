# Update Version 

### Follow these instructions to update the MTE version and push a new tag through to the public GitHub Repo.

1. Create a feature branch, i.e. 'update_to_version_x.x.x'
2. In azure-pipelines.yml, update the version in the build script and in the 'sed' lines which overwrite the Package.swift file for the purposes of building the package. It's critical that the part of the 'sed' command that corresponds to the Package.swift line be exactly the same as that is how it locates the line to change. Otherwise, we get a 'Failed to clone repository git@github.com:Eclypses/package-swift-ecdh.git:' type error
3. While not stricly necessary for minor version updates, update the dependency version in the Package.Swift file 
4. Right-click on 'Package Dependencies' in the File Navigator, and select 'Reset Package Caches'. This should go out to the public GitHub repo and pull the latest Swift Wrapper Package which will in turn, pull the correct version of the lib package. You can verify in the 'Package Dependencies' section of the File Navigator that you retrieved the correct version from the public repo.
5. Expand Package Dependencies > Mte > Sources > Mte, then right-click on mte.xcframework and select 'Show in Finder'. Replace the mte.xcframework directory with a valid mte.xcframework for this version.
6. Navigate to the Package.swift and 'Save', which will run the Package.swift file and build the Package. Correct any errors.
7. Currently, Xcode seems to struggle with all these changes at this point and I'm finding that if I quit and restart Xcode here, everything builds and resolves correctly. It's worth a try.
8. Commit your changes and tag the commit with the version number. 
9. Push the feature branch to Azure. Go there and check for the update and the new tag. These commands will create or update the tags and push the tag and commit.
- git tag -f <tag>
- git push --force origin <tag>
- git push
10. Create a PR to merge to master. The pipeline will delete any unnecessary files and push to the public GitHub repo.
