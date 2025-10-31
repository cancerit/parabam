def get_blueprints(struc_blueprint):
    structures = {
        # Count total reads
        "read_count": {"data": 0, "store_method": "cumu"},
        # Sum of all read lengths
        "total_length": {"data": 0, "store_method": "cumu"},
        # Longest read
        "max_length": {"data": 0, "store_method": "max"},
        # Shortest read (start high)
        "min_length": {"data": 999999, "store_method": "min"},
        # Count reads by quality
        "quality_counts": {"data": {}, "store_method": "cumu"}
    }
    struc_blueprint.update(structures)

def rule(read, constants, master):
    # Return values matching your blueprint keys
    return {
        "read_count": 1,
        "total_length": read.query_length,
        "max_length": read.query_length,
        "min_length": read.query_length,
        "quality_counts": {read.mapping_quality: 1}
    }
