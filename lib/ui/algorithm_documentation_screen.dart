import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/models/algorithm_metadata.dart';
import 'package:nt_helper/models/algorithm_parameter.dart';
import 'package:nt_helper/models/algorithm_port.dart';
import 'package:nt_helper/models/algorithm_specification.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';

class AlgorithmDocumentationScreen extends StatelessWidget {
  final AlgorithmMetadata metadata;

  const AlgorithmDocumentationScreen({super.key, required this.metadata});

  @override
  Widget build(BuildContext context) {
    // Get expanded parameters once to use for check and for the card itself.
    final expandedParams = AlgorithmMetadataService().getExpandedParameters(
      metadata.guid,
    );

    return Scaffold(
      appBar: AppBar(title: Text(metadata.name)),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildDescriptionCard(context),
          if (metadata.categories.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildCategoriesCard(context),
          ],
          if (metadata.inputPorts.isNotEmpty ||
              metadata.outputPorts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildPortsCard(context),
          ],
          if (metadata.specifications.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSpecificationsCard(context),
          ],
          if (expandedParams.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildParametersCard(context, expandedParams),
          ],
          if (metadata.features.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildFeaturesCard(context),
          ],
        ],
      ),
    );
  }

  Widget _buildDescriptionCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Description',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            Text(
              metadata.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Categories',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: metadata.categories
                  .map((category) => Chip(label: Text(category)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortsCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'I/O Ports',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            if (metadata.inputPorts.isNotEmpty) ...[
              Text('Inputs', style: Theme.of(context).textTheme.titleMedium),
              ...metadata.inputPorts.map((port) => _buildPortTile(port)),
            ],
            if (metadata.outputPorts.isNotEmpty) ...[
              SizedBox(height: metadata.inputPorts.isNotEmpty ? 16 : 0),
              Text('Outputs', style: Theme.of(context).textTheme.titleMedium),
              ...metadata.outputPorts.map((port) => _buildPortTile(port)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPortTile(AlgorithmPort port) {
    return ListTile(
      dense: true,
      leading: const ExcludeSemantics(
        child: Icon(Icons.arrow_circle_right_outlined),
      ),
      title: Text(port.name),
      subtitle: port.description != null ? Text(port.description!) : null,
    );
  }

  Widget _buildSpecificationsCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Specifications',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            ...metadata.specifications.map((spec) => _buildSpecTile(spec)),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecTile(AlgorithmSpecification spec) {
    final subtitleParts = <String>[];
    if (spec.description != null) {
      subtitleParts.add(spec.description!);
    }
    if (spec.value != null) {
      subtitleParts.add('Value: ${spec.value}');
    }
    if (spec.min != null) {
      subtitleParts.add('Min: ${spec.min}');
    }
    if (spec.max != null) {
      subtitleParts.add('Max: ${spec.max}');
    }

    return ListTile(
      dense: true,
      title: Text(spec.name),
      subtitle: Text(subtitleParts.join(' | ')),
    );
  }

  Widget _buildParametersCard(
    BuildContext context,
    List<AlgorithmParameter> expandedParams,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Parameters',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            ...expandedParams.map(
              (param) => _buildParameterTile(
                context,
                param,
                isLast: param == expandedParams.last,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParameterTile(
    BuildContext context,
    AlgorithmParameter param, {
    bool isLast = false,
  }) {
    final details = <String>[];
    if (param.type != null) details.add('Type: ${param.type}');
    if (param.unit != null) details.add('Unit: ${param.unit}');
    if (param.min != null) details.add('Min: ${param.min}');
    if (param.max != null) details.add('Max: ${param.max}');
    if (param.defaultValue != null) {
      details.add('Default: ${param.defaultValue}');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(param.name, style: Theme.of(context).textTheme.titleMedium),
          if (param.description != null) ...[
            const SizedBox(height: 4),
            Text(
              param.description!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details.join('  •  '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (param.enumValues != null && param.enumValues!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Values: ${param.enumValues!.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (!isLast) const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _buildFeaturesCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Features',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            ...metadata.features.map((featureGuid) {
              final feature = AlgorithmMetadataService().getFeatureByGuid(
                featureGuid,
              );
              if (feature == null) {
                return ListTile(title: Text('Unknown Feature: $featureGuid'));
              }
              return ExpansionTile(
                title: Text(feature.name),
                subtitle: Text(
                  feature.description ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(feature.description ?? ''),
                        const SizedBox(height: 16),
                        if (feature.parameters.isNotEmpty)
                          Text(
                            'Parameters from this feature:',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ...feature.parameters.map(
                          (p) => _buildParameterTile(
                            context,
                            p,
                            isLast: p == feature.parameters.last,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}
