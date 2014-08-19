class MappingsController < ApplicationController

  # Get mappings for a class
  get '/ontologies/:ontology/classes/:cls/mappings' do
    ontology = ontology_from_acronym(@params[:ontology])
    submission = ontology.latest_submission
    cls_id = @params[:cls]
    cls = LinkedData::Models::Class.find(RDF::URI.new(cls_id)).in(submission).first
    if cls.nil?
      reply 404, "Class with id `#{class_id}` not found in ontology `#{acronym}`" 
    end

    mappings = LinkedData::Mappings.mappings_ontology(submission,
                                                      0,0,
                                                      cls.id)
    reply mappings
  end

  # Get mappings for an ontology
  get '/ontologies/:ontology/mappings' do
    ontology = ontology_from_acronym(@params[:ontology])
    if ontology.nil?
        error(404, "Ontology not found")
    end
    page, size = page_params
    submission = ontology.latest_submission
    if submission.nil?
        error(404, "Submission not found for ontology " + ontology.acronym)
    end
    mappings = LinkedData::Mappings.mappings_ontology(submission,
                                                      page,size,
                                                      nil)
    reply mappings
  end

  namespace "/mappings" do
    # Display all mappings
    get do
      ontologies = ontology_objects_from_params
      if ontologies.length != 2
        error(400, 
              "/mappings/ endpoint only supports filtering " +
              "on two ontologies using `?ontologies=ONT1,ONT2`")
      end

      page, size = page_params
      ont1 = ontologies.first
      ont2 = ontologies[1]
      sub1, sub2 = ont1.latest_submission, ont2.latest_submission
      if sub1.nil?
        error(404, "Submission not found for ontology " + ontologies[0].id.to_s)
      end
      if sub2.nil?
        error(404, "Submission not found for ontology " + ontologies[1].id.to_s)
      end
      mappings = LinkedData::Mappings.mappings_ontologies(sub1,sub2,
                                                          page,size)
      reply mappings
    end

    get "/recent" do
      size = params[:size] || 5
      if size > 50
        error 422, "Recent mappings only processes calls under 50"
      else
        mappings = LinkedData::Mappings.recent_user_mappings(size + 15)
        #we load extra mappings because the filter might remove some
        reply filter_mappings_with_no_ontology(mappings)
        reply mappings[0..size-1]
      end
    end

    # Create a new mapping
    post do
      error(400, "Input does not contain classes") if !params[:classes]
      if params[:classes].length > 2
        error(400, "Input does not contain at least 2 terms")
      end
      error(400, "Input does not contain mapping relation") if !params[:relation]
      error(400, "Input does not contain user creator ID") if !params[:creator]
      classes = []
      params[:classes].each do |class_id,ontology_id|
        o = ontology_id
        o =  o.start_with?("http://") ? ontology_id :
                                        ontology_uri_from_acronym(ontology_id)
        o = LinkedData::Models::Ontology.find(RDF::URI.new(o))
                                        .include(submissions: 
                                       [:submissionId, :submissionStatus]).first
        if o.nil?
          error(400, "Ontology with ID `#{ontology_id}` not found")
        end
        submission = o.latest_submission
        if submission.nil?
          error(400, 
     "Ontology with id #{ontology_id} does not have parsed valid submission")
        end
        submission.bring(ontology: [:acronym])
        c = LinkedData::Models::Class.find(RDF::URI.new(class_id))
                                    .in(o.latest_submission)
                                    .first
        if c.nil?
          error(400, "Class ID `#{id}` not found in `#{submission.id.to_s}`")
        end
        classes << c
      end
      user_id = params[:creator].start_with?("http://") ? 
                    params[:creator].split("/")[-1] : params[:creator]
      user_creator = LinkedData::Models::User.find(user_id)
                          .include(:username).first
      if user_creator.nil?
        error(400, "User with id `#{params[:creator]}` not found")
      end
      process = LinkedData::Models::MappingProcess.new(
                    :creator => user_creator, :name => "REST Mapping")
      process.relation = RDF::URI.new(params[:relation])
      process.date = DateTime.now
      process_fields = [:source,:source_name, :comment]
      process_fields.each do |att|
        process.send("#{att}=",params[att]) if params[att]
      end
      process.save
      mapping = LinkedData::Mappings.create_rest_mapping(classes,process)
      reply(201, mapping)
    end

    # Delete a mapping
    delete '/:mapping' do
      mapping_id = RDF::URI.new(replace_url_prefix(params[:mapping]))
      mapping = LinkedData::Models::Mapping.find(mapping_id)
                  .include(terms: [:ontology, :term ])
                  .include(process: LinkedData::Models::MappingProcess.attributes)
                  .first

      if mapping.nil?
        error(404, "Mapping with id `#{mapping_id.to_s}` not found")
      else
        deleted = false
        disconnected = 0
        mapping.process.each do |p|
          if p.date
            disconnected += 1
            mapping_updated = LinkedData::Mappings.disconnect_mapping_process(mapping.id,p)
            if mapping_updated.process.length == 0
              deleted = true
              LinkedData::Mappings.delete_mapping(mapping_updated)
              break
            end
          end
        end

        if deleted
          halt 204
        else
          if disconnected > 0
            halt 204
          else
            reply(400, "This mapping only contains automatic processes. Nothing has been deleted")
          end
        end
      end
    end
  end

  namespace "/mappings/statistics" do

    get '/ontologies' do
      expires 86400, :public
      reply LinkedData::Mappings.mapping_counts_per_ontology()
    end

    # Statistics for an ontology
    get '/ontologies/:ontology' do
      expires 86400, :public
      ontology = ontology_from_acronym(@params[:ontology])
      reply LinkedData::Mappings.mapping_counts_for_ontology(ontology)
    end

    # Classes with lots of mappings
    get '/ontologies/:ontology/popular_classes' do
    end

    # Users with lots of mappings
    get '/ontologies/:ontology/users' do
    end
  end

end
